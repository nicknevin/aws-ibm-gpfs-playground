# AWS DR Analyzer Script

## Overview
This script analyzes AWS regions and availability zones to determine the best placement for disaster recovery (DR) instances. It provides comprehensive analysis including instance type availability, pricing information, and strategic recommendations.

## Features
- ✅ AWS credential validation
- 🌍 Region and availability zone analysis
- 🖥️ Instance type availability matrix across AZs
- 💰 Pricing information (spot prices)
- 🌐 Network performance analysis
- 🎯 DR setup recommendations
- 📋 Summary report generation

## Prerequisites
- AWS CLI installed and configured
- Valid AWS credentials
- `jq` (optional, for better JSON formatting)

## Usage

### Basic Usage
```bash
# Run with default AWS profile
./aws_dr_analyzer.sh

# Run with specific AWS profile
AWS_PROFILE_TO_CHECK="my-profile" ./aws_dr_analyzer.sh
```

### Environment Variables
- `AWS_PROFILE_TO_CHECK`: Specify AWS profile to use (optional)

## Script Output

The script provides several types of analysis:

### 1. Credential Validation
Verifies AWS credentials and displays account information.

### 2. Availability Zone Analysis
Shows all available AZs in the current region with their status.

### 3. Instance Type Availability Matrix
Displays a matrix showing which instance types are available in each AZ:
- ✅ Available
- ❌ Not available

### 4. Pricing Information
Shows recent spot pricing for sample instance types across AZs.

### 5. DR Recommendations
Provides specific recommendations for:
- Architecture design
- Data replication strategies
- Failover procedures
- Cost optimization

## Instance Types Analyzed
By default, the script checks these instance types:
- m5.large, m5.xlarge
- c5.large, c5.xlarge  
- t3.medium, t3.large

You can modify the `INSTANCE_TYPES_TO_CHECK` array in the script to check different types.

## Output Files
The script generates reports in the `reports/` subdirectory:
- Summary report: `reports/aws_dr_summary_YYYYMMDD_HHMMSS.txt`
- JSON data (if jq available): `reports/aws_dr_analysis_YYYYMMDD_HHMMSS.json`

## DR Best Practices Implemented

### Multi-AZ Strategy
- Primary and DR instances in different AZs
- Geographic separation for resilience
- Network performance optimization

### Cost Optimization
- Reserved Instance recommendations
- Spot Instance considerations
- Lifecycle policy suggestions

### Reliability
- Auto Scaling Group recommendations
- Health check implementation
- Regular DR testing procedures

## Troubleshooting

### Common Issues
1. **AWS CLI not found**: Install AWS CLI
2. **Credential errors**: Check `aws configure` or profile settings
3. **Permission errors**: Ensure IAM permissions for EC2 describe operations

### Required IAM Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeSpotPriceHistory",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

## Example Output
```
🚀 AWS DR Setup Analyzer
=========================
✅ AWS credentials are valid!
Account ID: 123456789012
User ARN: arn:aws:iam::123456789012:user/myuser

🌍 Current region: us-east-1

📍 Analyzing availability zones in region: us-east-1
us-east-1a: available (availability-zone)
us-east-1b: available (availability-zone)
us-east-1c: available (availability-zone)

🖥️ Checking instance type availability across AZs...
Instance Type   us-east-1a     us-east-1b     us-east-1c    
m5.large        ✅ Yes         ✅ Yes         ✅ Yes        
c5.large        ✅ Yes         ✅ Yes         ❌ No         

🎯 DR Setup Recommendations for region: us-east-1
1. 🏗️ Architecture Recommendations:
   • Use at least 2 different AZs for redundancy
   • Primary: Choose AZ with best instance type availability
   ...
```

## Next Steps
1. Review recommendations
2. Test instance launches in recommended AZs
3. Implement monitoring and alerting
4. Document DR procedures
5. Schedule regular DR testing
