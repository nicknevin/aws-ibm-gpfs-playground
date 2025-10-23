#!/bin/bash

# ==============================================================================
# AWS Access Key Checker Script
# This script verifies that the AWS CLI is configured with valid credentials
# by attempting to get the caller's identity.
# ==============================================================================

# Exit immediately if a command exits with a non-zero status.
# This ensures that the script stops if the 'aws' command fails.
set -e

# --- Configuration ---
# You can specify a profile to check, or leave it empty to use the default.
# For example:
# AWS_PROFILE_TO_CHECK="my-profile"
AWS_PROFILE_TO_CHECK=""

# --- Function to check for AWS CLI installation ---
check_aws_cli() {
  if ! command -v aws &> /dev/null
  then
    echo "Error: AWS CLI is not installed. Please install it to use this script."
    exit 1
  fi
}

# --- Main script logic ---
echo "Starting AWS credential check..."
echo "---------------------------------"

# Check for AWS CLI first
check_aws_cli

# Construct the AWS command with a profile if specified
AWS_COMMAND="aws sts get-caller-identity"
if [ ! -z "$AWS_PROFILE_TO_CHECK" ]; then
  AWS_COMMAND="$AWS_COMMAND --profile $AWS_PROFILE_TO_CHECK"
  echo "Checking credentials for profile: $AWS_PROFILE_TO_CHECK"
fi

# Execute the command and capture the output
# The 'get-caller-identity' command returns details about the IAM user,
# assuming the credentials are valid.
# We use 'set +e' and 'set -e' to handle the command's exit status gracefully.
set +e
OUTPUT=$($AWS_COMMAND 2>&1)
EXIT_CODE=$?
set -e

echo "Command executed: $AWS_COMMAND"
echo "---------------------------------"

# Check the exit code of the command
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ Success: Your AWS credentials are valid and working!"
  echo "---------------------------------"
  echo "Output:"
  echo "$OUTPUT"
else
  echo "❌ Error: The AWS command failed. Your credentials may be invalid or misconfigured."
  echo "---------------------------------"
  echo "Details:"
  echo "$OUTPUT"
  echo ""
  echo "Possible reasons:"
  echo "1. Invalid or expired Access Key ID/Secret Access Key."
  echo "2. No permissions to use the 'sts:GetCallerIdentity' action."
  echo "3. Incorrectly configured AWS profile."
fi

