# AWS EC2 Instance Monitor

A comprehensive script to monitor EC2 instances in AWS regions, specifically designed to show instance owners and launch times.

## Features

- **Region-specific monitoring**: Defaults to EU-North region but configurable
- **Owner identification**: Extracts owner information from multiple tag formats
- **Launch time tracking**: Shows when instances were launched
- **Storage monitoring**: Optional EBS volume details with size, type, state, and encryption status
- **Comprehensive instance details**: Includes state, type, IP addresses, names, and storage
- **Summary statistics**: Provides counts by state and instance type
- **Detailed reporting**: Generates timestamped reports in the reports directory
- **Flexible configuration**: Supports AWS profiles and custom regions

## Prerequisites

- AWS CLI installed and configured
- Valid AWS credentials with EC2 read permissions
- `jq` (optional but recommended for better output formatting)

## Installation

```bash
# Make the script executable
chmod +x aws_ec2_monitor.sh
```

## Usage

### Basic Usage
```bash
# Monitor EU-North region with default profile
./aws_ec2_monitor.sh
```

### Advanced Usage
```bash
# Use specific AWS profile
./aws_ec2_monitor.sh -p my-profile

# Monitor different region
./aws_ec2_monitor.sh -r us-east-1

# Combine options
./aws_ec2_monitor.sh -p production -r eu-west-1
```

### Command Line Options

- `-p, --profile PROFILE`: AWS profile to use
- `-r, --region REGION`: AWS region to monitor (default: eu-north-1)
- `-s, --storage`: Show EBS storage details for each instance
- `-h, --help`: Show help message

## Output

The script provides:

1. **Console Output**: Formatted table showing:
   - Instance ID
   - State (running, stopped, pending)
   - Instance Type
   - Launch Time
   - Public IP Address
   - Private IP Address
   - Instance Name
   - Owner (from tags)
   - Storage Details (when using `-s` option): EBS volume ID, size, type, state, encryption status

2. **Summary Statistics**: 
   - Total instance count
   - Count by state
   - Count by instance type

3. **Detailed Report**: Saved to `reports/ec2_monitor_YYYYMMDD_HHMMSS.txt`

## Owner Tag Detection

The script looks for owner information in the following tag keys (in order of priority):
- `Owner`
- `owner`
- `CreatedBy`
- `created-by`
- `User`
- `user`

## Example Output

```
📊 EC2 Instances in eu-north-1
==============================
Instance ID          | State      | Type         | Launch Time           | Public IP    | Private IP   | Name                | Owner
--------------------|------------|--------------|----------------------|--------------|--------------|---------------------|------------------
i-1234567890abcdef0 | running    | t3.micro     | 2024-01-15T10:30:00Z | 1.2.3.4      | 10.0.1.100   | web-server-01       | john.doe@company.com
i-0987654321fedcba0 | stopped    | m5.large     | 2024-01-14T15:45:00Z | N/A          | 10.0.1.101   | database-server     | jane.smith@company.com

Storage Information:
Instance ID          | Storage Details
--------------------|----------------------------------------
i-1234567890abcdef0 | vol-abc123: 30GB gp3 (in-use, encrypted)
i-0987654321fedcba0 | vol-def456: 100GB gp2 (in-use, unencrypted)

📈 Instance Summary Statistics
================================
Total Instances: 2
Running: 1
Stopped: 1
Pending: 0

Instance Types:
m5.large: 1
t3.micro: 1
```

## Error Handling

The script includes comprehensive error handling for:
- Missing AWS CLI
- Invalid credentials
- Network connectivity issues
- Permission problems
- Empty result sets

## Reports

All reports are saved in the `reports/` directory with timestamps:
- `ec2_monitor_YYYYMMDD_HHMMSS.txt`

## Integration

This script can be integrated into:
- Monitoring dashboards
- Automated reporting systems
- CI/CD pipelines
- Scheduled cron jobs

## Security Notes

- The script only requires read permissions for EC2 instances
- No sensitive data is logged
- Credentials are handled through AWS CLI configuration
- Reports are stored locally only

## Troubleshooting

### Common Issues

1. **"AWS CLI is not installed"**
   - Install AWS CLI: `sudo dnf install awscli` (Fedora/RHEL)

2. **"AWS credential validation failed"**
   - Run `aws configure` to set up credentials
   - Check profile with `aws configure list-profiles`

3. **"No instances found"**
   - Verify you're checking the correct region
   - Ensure you have EC2 instances in the specified region
   - Check AWS permissions

4. **"jq is not installed"**
   - Install jq: `sudo dnf install jq` (Fedora/RHEL)
   - Script will work without jq but with limited formatting

### Required AWS Permissions

The script requires the following AWS permissions:
- `ec2:DescribeInstances`
- `ec2:DescribeTags`
- `sts:GetCallerIdentity`
