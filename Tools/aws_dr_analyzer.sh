#!/bin/bash

# ==============================================================================
# AWS DR Setup Analyzer Script
# This script analyzes AWS regions and availability zones to determine
# the best placement for disaster recovery instances.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration ---
AWS_PROFILE_TO_CHECK=""
REPORTS_DIR="reports"
OUTPUT_FILE="${REPORTS_DIR}/aws_dr_analysis_$(date +%Y%m%d_%H%M%S).json"
INSTANCE_TYPES_TO_CHECK=("m5.large" "m5.xlarge" "c5.large" "c5.xlarge" "t3.medium" "t3.large")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# --- Function to get current region ---
get_current_region() {
    local aws_command="aws configure get region"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    local region
    region=$($aws_command 2>/dev/null || echo "")
    
    if [ -z "$region" ]; then
        # Try to get from instance metadata if running on EC2
        region=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
    fi
    
    echo "$region"
}

# --- Function to analyze availability zones ---
analyze_availability_zones() {
    local region=$1
    print_status $BLUE "\n📍 Analyzing availability zones in region: $region"
    
    local aws_command="aws ec2 describe-availability-zones --region $region"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    local az_data
    az_data=$($aws_command)
    
    echo "$az_data" | jq -r '.AvailabilityZones[] | "\(.ZoneName): \(.State) (\(.ZoneType))"' 2>/dev/null || {
        echo "$az_data" | grep -o '"ZoneName": "[^"]*"' | cut -d'"' -f4
    }
}

# --- Function to check instance type availability in AZs ---
check_instance_availability() {
    local region=$1
    print_status $BLUE "\n🖥️  Checking instance type availability across AZs..."
    
    local aws_command_base="aws ec2 describe-instance-type-offerings --region $region"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command_base="$aws_command_base --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    # Get all AZs first
    local azs
    azs=$(aws ec2 describe-availability-zones --region $region --query 'AvailabilityZones[].ZoneName' --output text)
    
    echo "Instance Type Availability Matrix:"
    echo "=================================="
    printf "%-15s" "Instance Type"
    for az in $azs; do
        printf "%-15s" "$az"
    done
    echo ""
    
    for instance_type in "${INSTANCE_TYPES_TO_CHECK[@]}"; do
        printf "%-15s" "$instance_type"
        
        for az in $azs; do
            local available
            available=$($aws_command_base --location-type availability-zone --filters Name=location,Values=$az Name=instance-type,Values=$instance_type --query 'InstanceTypeOfferings[0].InstanceType' --output text 2>/dev/null)
            
            if [ "$available" = "$instance_type" ]; then
                printf "%-15s" "✅ Yes"
            else
                printf "%-15s" "❌ No"
            fi
        done
        echo ""
    done
}

# --- Function to get pricing information (simplified) ---
get_pricing_info() {
    local region=$1
    print_status $BLUE "\n💰 Getting pricing information for region: $region"
    
    # Note: This is a simplified approach. For comprehensive pricing,
    # you would need to use the AWS Price List API
    print_status $YELLOW "Note: For detailed pricing, use AWS Price List API or AWS Cost Explorer"
    
    local aws_command="aws ec2 describe-spot-price-history --region $region --max-items 5 --instance-types m5.large"
    if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
        aws_command="$aws_command --profile $AWS_PROFILE_TO_CHECK"
    fi
    
    print_status $BLUE "Recent spot prices for m5.large:"
    $aws_command --query 'SpotPriceHistory[*].[AvailabilityZone,SpotPrice,Timestamp]' --output table 2>/dev/null || {
        print_status $YELLOW "Unable to retrieve spot pricing information"
    }
}

# --- Function to analyze network performance between AZs ---
analyze_network_performance() {
    local region=$1
    print_status $BLUE "\n🌐 Network Performance Analysis"
    
    print_status $BLUE "Cross-AZ network performance characteristics:"
    echo "• Same AZ: Highest performance, lowest latency (~0.1-0.5ms)"
    echo "• Cross-AZ: Good performance, low latency (~1-2ms)"
    echo "• Cross-Region: Variable performance, higher latency (>20ms)"
    echo ""
    print_status $YELLOW "For DR setup, consider:"
    echo "• Place primary and DR instances in different AZs within the same region"
    echo "• For maximum resilience, consider cross-region DR"
    echo "• Use placement groups for high-performance clustering within AZ"
}

# --- Function to provide DR recommendations ---
provide_dr_recommendations() {
    local region=$1
    print_status $GREEN "\n🎯 DR Setup Recommendations for region: $region"
    
    echo "1. 🏗️  Architecture Recommendations:"
    echo "   • Use at least 2 different AZs for redundancy"
    echo "   • Primary: Choose AZ with best instance type availability"
    echo "   • DR: Choose different AZ with similar instance availability"
    echo "   • Consider using Auto Scaling Groups across multiple AZs"
    echo ""
    
    echo "2. 📊 Data Replication:"
    echo "   • Use EBS snapshots for backup and DR"
    echo "   • Consider Cross-Region replication for critical data"
    echo "   • Use RDS Multi-AZ for database redundancy"
    echo ""
    
    echo "3. 🔄 Failover Strategy:"
    echo "   • Implement health checks and automatic failover"
    echo "   • Use Route 53 for DNS-based failover"
    echo "   • Test DR procedures regularly"
    echo ""
    
    echo "4. 💡 Cost Optimization:"
    echo "   • Use Reserved Instances for predictable workloads"
    echo "   • Consider Spot Instances for non-critical DR testing"
    echo "   • Implement lifecycle policies for snapshots"
    echo ""
    
    print_status $BLUE "Best AZ Selection Criteria:"
    echo "• ✅ High instance type availability"
    echo "• ✅ Stable pricing history"
    echo "• ✅ Geographic separation from primary AZ"
    echo "• ✅ Network performance requirements met"
}

# --- Function to generate summary report ---
generate_summary_report() {
    local region=$1
    print_status $BLUE "\n📋 Generating Summary Report..."
    
    # Create reports directory if it doesn't exist
    mkdir -p "$REPORTS_DIR"
    
    local report_file="${REPORTS_DIR}/aws_dr_summary_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "AWS DR Analysis Report"
        echo "====================="
        echo "Generated: $(date)"
        echo "Region: $region"
        echo "Profile: ${AWS_PROFILE_TO_CHECK:-default}"
        echo ""
        echo "This analysis provides recommendations for DR instance placement."
        echo "For detailed implementation, consult AWS Well-Architected Framework."
    } > "$report_file"
    
    print_status $GREEN "✅ Summary report saved to: $report_file"
}

# --- Main script execution ---
main() {
    print_status $GREEN "🚀 AWS DR Setup Analyzer"
    print_status $GREEN "========================="
    
    # Check prerequisites
    check_aws_cli
    local has_jq
    has_jq=$(check_jq && echo "true" || echo "false")
    
    # Validate credentials
    validate_credentials
    
    # Get current region
    local current_region
    current_region=$(get_current_region)
    print_status $BLUE "\n🌍 Current region: $current_region"
    
    # Analyze availability zones
    analyze_availability_zones "$current_region"
    
    # Check instance availability
    check_instance_availability "$current_region"
    
    # Get pricing information
    get_pricing_info "$current_region"
    
    # Analyze network performance
    analyze_network_performance "$current_region"
    
    # Provide recommendations
    provide_dr_recommendations "$current_region"
    
    # Generate summary report
    generate_summary_report "$current_region"
    
    print_status $GREEN "\n✅ DR Analysis Complete!"
    print_status $BLUE "Reports saved in: ./$REPORTS_DIR/"
    print_status $BLUE "Next steps:"
    echo "1. Review the recommendations above"
    echo "2. Test instance launches in recommended AZs"
    echo "3. Implement monitoring and alerting"
    echo "4. Document your DR procedures"
}

# --- Script entry point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
