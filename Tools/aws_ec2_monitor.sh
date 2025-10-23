#!/bin/bash

# ==============================================================================
# AWS EC2 Instance Monitor Script
# This script monitors EC2 instances in the EU-North region and displays
# instance information including owner and launch time.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
AWS_PROFILE_TO_CHECK=""
REGION="eu-north-1"
REPORTS_DIR="reports"
OUTPUT_FILE="${REPORTS_DIR}/ec2_monitor_$(date +%Y%m%d_%H%M%S).txt"
SHOW_STORAGE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to print colored output ---
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# --- Function to check for AWS CLI installation ---
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_status $RED "Error: AWS CLI is not installed. Please install it to use this script."
        exit 1
    fi
}

# --- Function to check for jq installation ---
check_jq() {
    if ! command -v jq &> /dev/null; then
        print_status $YELLOW "Warning: jq is not installed. JSON output will be limited."
        print_status $YELLOW "Install jq for better formatted output: sudo dnf install jq"
        return 1
    fi
    return 0
}

# --- Function to validate AWS region ---
validate_region() {
    local region=$1
    print_status $BLUE "Validating AWS region: $region"
    
    # List of valid AWS regions (as of 2024)
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1" "eu-south-1"
        "ap-southeast-1" "ap-southeast-2" "ap-southeast-3" "ap-southeast-4"
        "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-south-1"
        "ca-central-1" "sa-east-1" "af-south-1" "me-south-1" "me-central-1"
    )
    
    for valid_region in "${valid_regions[@]}"; do
        if [ "$region" = "$valid_region" ]; then
            print_status $GREEN "✅ Valid region: $region"
            return 0
        fi
    done
    
    print_status $RED "❌ Invalid region: $region"
    print_status $YELLOW "Valid regions include:"
    printf "  %s\n" "${valid_regions[@]}"
    exit 1
}

# --- Function to validate AWS credentials ---
validate_credentials() {
    print_status $BLUE "Validating AWS credentials..."
    
    local aws_command="aws sts get-caller-identity"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
        print_status $BLUE "Using profile: $AWS_PROFILE_TO_CHECK"
    fi
    
    set +e
    local output
    output=$($aws_command 2>&1)
    local exit_code=$?
    set -e
    
    if [ $exit_code -eq 0 ]; then
        print_status $GREEN "✅ AWS credentials are valid!"
        local account_id=$(echo "$output" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        local user_arn=$(echo "$output" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
        print_status $BLUE "Account ID: $account_id"
        print_status $BLUE "User ARN: $user_arn"
        return 0
    else
        print_status $RED "❌ AWS credential validation failed!"
        print_status $RED "$output"
        exit 1
    fi
}

# --- Function to get EBS volume details ---
get_ebs_volume_details() {
    local volume_ids=$1
    local aws_command="aws ec2 describe-volumes --region $REGION"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    # Debug: Show what we received
    # echo "DEBUG: Received volume_ids: $volume_ids"
    
    if [ -z "$volume_ids" ] || [ "$volume_ids" = "null" ] || [ "$volume_ids" = "[]" ] || [ "$volume_ids" = "No volumes" ]; then
        echo "No volumes"
        return
    fi
    
    # Convert volume IDs array to space-separated string for AWS CLI
    # First try to parse as JSON array, if that fails, try to extract volume IDs from string
    local volume_list=$(echo "$volume_ids" | jq -r '.[]' 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    
    # If jq failed, try to extract volume IDs using grep
    if [ -z "$volume_list" ] || [ "$volume_list" = "null" ]; then
        volume_list=$(echo "$volume_ids" | grep -o 'vol-[a-f0-9]*' | tr '\n' ' ' | sed 's/ $//')
    fi
    
    # Debug: Show the processed volume list
    # echo "DEBUG: Processed volume_list: $volume_list"
    
    if [ -z "$volume_list" ] || [ "$volume_list" = "null" ]; then
        echo "No volumes"
        return
    fi
    
    set +e
    local volume_data=$($aws_command --volume-ids $volume_list --query 'Volumes[*].[VolumeId,Size,VolumeType,State,Encrypted]' --output json 2>/dev/null)
    local aws_exit_code=$?
    set -e
    
    if [ $aws_exit_code -eq 0 ] && [ ! -z "$volume_data" ]; then
        echo "$volume_data" | jq -r '.[] | "\(.[0]): \(.[1])GB \(.[2]) (\(.[3]), \(if .[4] then "encrypted" else "unencrypted" end))"' 2>/dev/null | tr '\n' '; ' | sed 's/; $//'
    else
        echo "Volume details unavailable"
    fi
}

# --- Function to get EC2 instances with detailed information ---
get_ec2_instances() {
    local aws_command="aws ec2 describe-instances --region $REGION"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    # Get instances with all details including tags and storage
    local instances_data
    set +e  # Temporarily disable exit on error
    instances_data=$($aws_command --query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,LaunchTime,PublicIpAddress,PrivateIpAddress,Tags[?Key==`Name`].Value|[0],Tags[?Key==`Owner`].Value|[0],Tags[?Key==`owner`].Value|[0],Tags[?Key==`CreatedBy`].Value|[0],Tags[?Key==`created-by`].Value|[0],Tags[?Key==`User`].Value|[0],Tags[?Key==`user`].Value|[0],BlockDeviceMappings[].Ebs.VolumeId]' --output json 2>&1)
    local aws_exit_code=$?
    set -e  # Re-enable exit on error
    
    if [ $aws_exit_code -ne 0 ]; then
        print_status $RED "Error calling AWS API:"
        print_status $RED "$instances_data"
        exit 1
    fi
    
    echo "$instances_data"
}

# --- Function to display instances using fallback parsing ---
display_instances_fallback() {
    local instances_data=$1
    
    echo "Instance ID          | State      | Type         | Launch Time           | Public IP    | Private IP   | Name                | Owner"
    echo "--------------------|------------|--------------|----------------------|--------------|--------------|---------------------|------------------"
    
    # Check if we have any data at all
    if [ -z "$instances_data" ] || [ "$instances_data" = "[]" ] || [ "$instances_data" = "null" ]; then
        echo "No instances found in region $REGION"
        return
    fi
    
    # Debug: Show what data we received (uncomment for debugging)
    # echo "DEBUG: Received data: $instances_data"
    
    # Try to extract instance data using basic text processing
    # First, let's try a simpler approach - look for instance IDs
    echo "$instances_data" | grep -o 'i-[a-f0-9]*' | while read -r instance_id; do
        if [ ! -z "$instance_id" ]; then
            # Extract the line containing this instance ID
            local line=$(echo "$instances_data" | grep -A 20 "\"$instance_id\"" | head -1)
            if [ ! -z "$line" ]; then
                # Parse the JSON array manually
                local state=$(echo "$line" | sed 's/.*"\(running\|stopped\|pending\|terminated\|shutting-down\)".*/\1/')
                local instance_type=$(echo "$line" | sed 's/.*"\([a-z0-9.]*\)".*/\1/' | grep -E '^[a-z][0-9]+\.[a-z0-9]+$' | head -1)
                local launch_time=$(echo "$line" | sed 's/.*"\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}[^"]*\)".*/\1/')
                local public_ip=$(echo "$line" | grep -o '"[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}"' | head -1 | tr -d '"')
                local private_ip=$(echo "$line" | grep -o '"[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}"' | tail -1 | tr -d '"')
                local name=$(echo "$line" | grep -o '"dr-[^"]*"' | head -1 | tr -d '"')
                local owner=$(echo "$line" | grep -o '"nlevanon"' | head -1 | tr -d '"')
                
                # Handle null/empty values
                [ -z "$public_ip" ] && public_ip="N/A"
                [ -z "$private_ip" ] && private_ip="N/A"
                [ -z "$name" ] && name="N/A"
                [ -z "$owner" ] && owner="N/A"
                [ -z "$state" ] && state="unknown"
                [ -z "$instance_type" ] && instance_type="unknown"
                [ -z "$launch_time" ] && launch_time="N/A"
                
                # Format the output
                printf "%-20s | %-10s | %-12s | %-20s | %-12s | %-12s | %-19s | %s\n" \
                    "$instance_id" "$state" "$instance_type" "$launch_time" \
                    "$public_ip" "$private_ip" "$name" "$owner"
            fi
        fi
    done
    
    # Alternative approach - try to parse JSON arrays directly
    echo "$instances_data" | grep -o '\["[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*"\]' | while read -r line; do
        if [ ! -z "$line" ]; then
            # Extract values from JSON array using a more robust method
            local instance_id=$(echo "$line" | sed 's/\["\([^"]*\)".*/\1/')
            local state=$(echo "$line" | sed 's/\["[^"]*","\([^"]*\)".*/\1/')
            local instance_type=$(echo "$line" | sed 's/\["[^"]*","[^"]*","\([^"]*\)".*/\1/')
            local launch_time=$(echo "$line" | sed 's/\["[^"]*","[^"]*","[^"]*","\([^"]*\)".*/\1/')
            local public_ip=$(echo "$line" | sed 's/\["[^"]*","[^"]*","[^"]*","[^"]*","\([^"]*\)".*/\1/')
            local private_ip=$(echo "$line" | sed 's/\["[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","\([^"]*\)".*/\1/')
            local name=$(echo "$line" | sed 's/\["[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","\([^"]*\)".*/\1/')
            local owner=$(echo "$line" | sed 's/\["[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","[^"]*","\([^"]*\)".*/\1/')
            
            # Handle null values
            [ "$public_ip" = "null" ] && public_ip="N/A"
            [ "$private_ip" = "null" ] && private_ip="N/A"
            [ "$name" = "null" ] && name="N/A"
            [ "$owner" = "null" ] && owner="N/A"
            
            # Format the output
            printf "%-20s | %-10s | %-12s | %-20s | %-12s | %-12s | %-19s | %s\n" \
                "$instance_id" "$state" "$instance_type" "$launch_time" \
                "$public_ip" "$private_ip" "$name" "$owner"
        fi
    done
    
    # If no instances were found with the above method, show a message
    local instance_count=$(echo "$instances_data" | grep -c '\["[^"]*"' 2>/dev/null || echo "0")
    # Ensure instance_count is a valid integer
    if ! [[ "$instance_count" =~ ^[0-9]+$ ]]; then
        instance_count=0
    fi
    if [ "$instance_count" -eq 0 ]; then
        echo "No instances found in region $REGION"
    fi
}

# --- Function to format and display instance information with storage ---
display_instances_with_storage() {
    local instances_data=$1
    
    print_status $CYAN "\n📊 EC2 Instances with Storage in $REGION"
    print_status $CYAN "=========================================="
    
    # Check if we have any data at all first
    if [ -z "$instances_data" ] || [ "$instances_data" = "[]" ] || [ "$instances_data" = "null" ]; then
        echo ""
        print_status $YELLOW "No EC2 instances found in region $REGION"
        echo ""
        return
    fi
    
    # Display basic instance information first
    echo ""
    print_status $BLUE "Instance Information:"
    echo "Instance ID          | State      | Type         | Launch Time           | Public IP    | Private IP   | Name                | Owner"
    echo "--------------------|------------|--------------|----------------------|--------------|--------------|---------------------|------------------"
    
    if command -v jq &> /dev/null; then
        # Use jq for better formatting with error handling
        set +e  # Temporarily disable exit on error for jq
        echo "$instances_data" | jq -r '.[] | .[] | if .[0] != null then "\(.[0] // "N/A") | \(.[1] // "N/A") | \(.[2] // "N/A") | \(.[3] // "N/A") | \(.[4] // "N/A") | \(.[5] // "N/A") | \(.[6] // "N/A") | \(.[7] // .[8] // .[9] // .[10] // .[11] // .[12] // "N/A")" else empty end' 2>/dev/null
        set -e  # Re-enable exit on error
    else
        # Fallback formatting without jq
        display_instances_fallback "$instances_data"
    fi
    
    # Now display storage information for each instance
    echo ""
    print_status $BLUE "Storage Information:"
    echo "Instance ID          | Storage Details"
    echo "--------------------|----------------------------------------"
    
    if command -v jq &> /dev/null; then
        echo "$instances_data" | jq -r '.[] | .[] | if .[0] != null then "\(.[0]) | \(.[-1] // "[]")" else empty end' 2>/dev/null | while read -r line; do
            if [ ! -z "$line" ]; then
                local instance_id=$(echo "$line" | cut -d'|' -f1 | xargs)
                local volume_ids=$(echo "$line" | cut -d'|' -f2 | xargs)
                
                if [ "$volume_ids" != "[]" ] && [ "$volume_ids" != "null" ] && [ ! -z "$volume_ids" ]; then
                    # Debug: Show what we're passing to the function
                    # echo "DEBUG: Processing instance $instance_id with volumes: $volume_ids"
                    local volume_details=$(get_ebs_volume_details "$volume_ids")
                    printf "%-20s | %s\n" "$instance_id" "$volume_details"
                else
                    printf "%-20s | No EBS volumes attached\n" "$instance_id"
                fi
            fi
        done
    else
        echo "Install jq for detailed storage information"
    fi
}

# --- Function to format and display instance information ---
display_instances() {
    local instances_data=$1
    
    print_status $CYAN "\n📊 EC2 Instances in $REGION"
    print_status $CYAN "=============================="
    
    # Check if we have any data at all first
    if [ -z "$instances_data" ] || [ "$instances_data" = "[]" ] || [ "$instances_data" = "null" ]; then
        echo ""
        print_status $YELLOW "No EC2 instances found in region $REGION"
        echo ""
        return
    fi
    
    # Check if we have jq for better formatting
    if command -v jq &> /dev/null; then
        # Use jq for better formatting with error handling
        local jq_output
        set +e  # Temporarily disable exit on error for jq
        jq_output=$(echo "$instances_data" | jq -r --arg region "$REGION" 'if length > 0 then "Instance ID          | State      | Type         | Launch Time           | Public IP    | Private IP   | Name                | Owner", "--------------------|------------|--------------|----------------------|--------------|--------------|---------------------|------------------", (.[] | .[] | if .[0] != null then "\(.[0] // "N/A") | \(.[1] // "N/A") | \(.[2] // "N/A") | \(.[3] // "N/A") | \(.[4] // "N/A") | \(.[5] // "N/A") | \(.[6] // "N/A") | \(.[7] // .[8] // .[9] // .[10] // .[11] // .[12] // "N/A")" else empty end) else "No instances found in region " + $region end' 2>/dev/null)
        local jq_exit_code=$?
        set -e  # Re-enable exit on error
        
        if [ $jq_exit_code -eq 0 ] && [ ! -z "$jq_output" ]; then
            echo "$jq_output"
        else
            # Fallback to manual parsing if jq fails
            print_status $YELLOW "jq parsing failed, using fallback formatting..."
            display_instances_fallback "$instances_data"
        fi
    else
        # Fallback formatting without jq
        display_instances_fallback "$instances_data"
    fi
}

# --- Function to get instance summary statistics ---
get_instance_summary() {
    local instances_data=$1
    
    print_status $BLUE "\n📈 Instance Summary Statistics"
    print_status $BLUE "================================"
    
    if command -v jq &> /dev/null; then
        # Try to use jq for statistics with error handling
        local jq_stats=$(echo "$instances_data" | jq '[.[] | .[] | select(.[0] != null)] | length' 2>/dev/null)
        
        if [ $? -eq 0 ] && [ ! -z "$jq_stats" ]; then
            # Count instances by state
            local running_count=$(echo "$instances_data" | jq '[.[] | .[] | select(.[0] != null and .[1] == "running")] | length' 2>/dev/null || echo "0")
            local stopped_count=$(echo "$instances_data" | jq '[.[] | .[] | select(.[0] != null and .[1] == "stopped")] | length' 2>/dev/null || echo "0")
            local pending_count=$(echo "$instances_data" | jq '[.[] | .[] | select(.[0] != null and .[1] == "pending")] | length' 2>/dev/null || echo "0")
            local total_count="$jq_stats"
            
            echo "Total Instances: $total_count"
            echo "Running: $running_count"
            echo "Stopped: $stopped_count"
            echo "Pending: $pending_count"
            
            # Count by instance type
            print_status $BLUE "\nInstance Types:"
            echo "$instances_data" | jq -r '[.[] | .[] | select(.[0] != null) | .[2]] | group_by(.) | map({type: .[0], count: length}) | .[] | "\(.type): \(.count)"' 2>/dev/null | sort || echo "Unable to parse instance types"
        else
            # Fallback to basic counting
            print_status $YELLOW "jq parsing failed, using basic statistics..."
            local total_count=$(echo "$instances_data" | grep -c '\["[^"]*"' 2>/dev/null || echo "0")
            echo "Total Instances: $total_count"
            echo "Note: Install jq for detailed statistics"
        fi
    else
        print_status $YELLOW "Install jq for detailed statistics"
        local total_count=$(echo "$instances_data" | grep -c '\["[^"]*"' 2>/dev/null || echo "0")
        echo "Total Instances: $total_count"
    fi
}

# --- Function to generate detailed report ---
generate_detailed_report() {
    local instances_data=$1
    
    print_status $BLUE "\n📋 Generating Detailed Report..."
    
    # Create reports directory if it doesn't exist
    mkdir -p "$REPORTS_DIR"
    
    {
        echo "AWS EC2 Instance Monitor Report"
        echo "==============================="
        echo "Generated: $(date)"
        echo "Region: $REGION"
        echo "Profile: ${AWS_PROFILE_TO_CHECK:-default}"
        echo ""
        echo "Instance Details:"
        echo "================="
        
        if command -v jq &> /dev/null; then
            set +e  # Temporarily disable exit on error
            local jq_report=$(echo "$instances_data" | jq -r '
                if length > 0 then
                    (.[] | .[] | 
                        if .[0] != null then
                            "Instance ID: \(.[0])",
                            "State: \(.[1])",
                            "Type: \(.[2])",
                            "Launch Time: \(.[3])",
                            "Public IP: \(.[4] // "N/A")",
                            "Private IP: \(.[5] // "N/A")",
                            "Name: \(.[6] // "N/A")",
                            "Owner: \(.[7] // .[8] // .[9] // .[10] // .[11] // .[12] // "N/A")",
                            "----------------------------------------"
                        else empty
                        end)
                else
                    "No instances found in region"
                end
            ' 2>/dev/null)
            set -e  # Re-enable exit on error
            
            if [ $? -eq 0 ] && [ ! -z "$jq_report" ]; then
                echo "$jq_report"
            else
                echo "$instances_data"
            fi
        else
            echo "$instances_data"
        fi
    } > "$OUTPUT_FILE"
    
    print_status $GREEN "✅ Detailed report saved to: $OUTPUT_FILE"
}

# --- Function to show available regions ---
show_regions() {
    print_status $CYAN "🌍 Available AWS Regions"
    print_status $CYAN "========================"
    echo ""
    
    local valid_regions=(
        "us-east-1" "us-east-2" "us-west-1" "us-west-2"
        "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1" "eu-south-1"
        "ap-southeast-1" "ap-southeast-2" "ap-southeast-3" "ap-southeast-4"
        "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-south-1"
        "ca-central-1" "sa-east-1" "af-south-1" "me-south-1" "me-central-1"
    )
    
    print_status $BLUE "Americas:"
    echo "  us-east-1 (N. Virginia)    us-east-2 (Ohio)"
    echo "  us-west-1 (N. California) us-west-2 (Oregon)"
    echo "  ca-central-1 (Canada)    sa-east-1 (São Paulo)"
    echo ""
    
    print_status $BLUE "Europe:"
    echo "  eu-west-1 (Ireland)      eu-west-2 (London)"
    echo "  eu-west-3 (Paris)        eu-central-1 (Frankfurt)"
    echo "  eu-north-1 (Stockholm)   eu-south-1 (Milan)"
    echo ""
    
    print_status $BLUE "Asia Pacific:"
    echo "  ap-southeast-1 (Singapore) ap-southeast-2 (Sydney)"
    echo "  ap-southeast-3 (Jakarta)  ap-southeast-4 (Melbourne)"
    echo "  ap-northeast-1 (Tokyo)    ap-northeast-2 (Seoul)"
    echo "  ap-northeast-3 (Osaka)    ap-south-1 (Mumbai)"
    echo ""
    
    print_status $BLUE "Middle East & Africa:"
    echo "  me-south-1 (Bahrain)     me-central-1 (UAE)"
    echo "  af-south-1 (Cape Town)"
    echo ""
    
    print_status $GREEN "Usage Examples:"
    echo "  ./aws_ec2_monitor.sh -r us-east-1    # Monitor US East"
    echo "  ./aws_ec2_monitor.sh -r eu-west-1    # Monitor EU West"
    echo "  ./aws_ec2_monitor.sh -r ap-southeast-1 # Monitor Asia Pacific"
}

# --- Function to show help information ---
show_help() {
    echo "AWS EC2 Instance Monitor"
    echo "======================="
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --profile PROFILE    AWS profile to use"
    echo "  -r, --region REGION      AWS region to monitor (default: eu-north-1)"
    echo "  -s, --storage            Show EBS storage details for each instance"
    echo "  -l, --list-regions       Show available AWS regions"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Monitor eu-north-1 with default profile"
    echo "  $0 -p my-profile        # Use specific AWS profile"
    echo "  $0 -r us-east-1         # Monitor different region"
    echo "  $0 -s                   # Show instances with storage details"
    echo "  $0 -l                   # List available regions"
    echo ""
    echo "This script displays EC2 instances with their owners and launch times."
    echo "Owner information is extracted from common tag names: Owner, owner, CreatedBy, created-by, User, user"
}

# --- Function to parse command line arguments ---
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--profile)
                AWS_PROFILE_TO_CHECK="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -s|--storage)
                SHOW_STORAGE=true
                shift
                ;;
            -l|--list-regions)
                show_regions
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_status $RED "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# --- Main script execution ---
main() {
    print_status $GREEN "🚀 AWS EC2 Instance Monitor"
    print_status $GREEN "============================"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_aws_cli
    local has_jq
    has_jq=$(check_jq && echo "true" || echo "false")
    
    # Validate region
    validate_region "$REGION"
    
    # Validate credentials
    validate_credentials
    
    # Get EC2 instances
    print_status $BLUE "\n🔍 Retrieving EC2 instances from region: $REGION"
    local instances_data
    instances_data=$(get_ec2_instances)
    
    # Debug: Check if we got data
    if [ -z "$instances_data" ]; then
        print_status $RED "Error: No data received from AWS API"
        exit 1
    fi
    
    # Display instances
    if [ "$SHOW_STORAGE" = true ]; then
        display_instances_with_storage "$instances_data"
    else
        display_instances "$instances_data"
    fi
    
    # Show summary statistics
    get_instance_summary "$instances_data"
    
    # Generate detailed report
    generate_detailed_report "$instances_data"
    
    print_status $GREEN "\n✅ EC2 Monitoring Complete!"
    print_status $BLUE "Reports saved in: ./$REPORTS_DIR/"
    print_status $BLUE "Next steps:"
    echo "1. Review the instance list above"
    echo "2. Check the detailed report for more information"
    echo "3. Set up CloudWatch alarms for monitoring"
    echo "4. Consider implementing automated tagging for better ownership tracking"
}

# --- Script entry point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
