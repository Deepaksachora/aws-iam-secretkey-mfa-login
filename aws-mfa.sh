#!/usr/bin/env bash
set -e
# Script generates a AWS Session Token and setup a profile with MFA. Before using this script ensure that packages AWS CLI
# and jq are installed and you have configured AWS CLI initial profile with
# aws configure
# or
# aws configure --profile <profile name>
# Script will ask you for the source profile name, if you didn't provide any profile name then enter, script will take the
# default profile, else provide the profile name.

# Check that AWS CLI is installed

AWSCLI=$(which aws)

if [ $? -eq 0 ]; then
  echo ""
else
  echo "AWS CLI is not installed, Please install AWS CLI"
fi

# Check that JQ is installed

JQ=$(which jq)

if [ $? -eq 0 ]; then
  echo ""
else
  echo "jq is not installed, Please install jq"
fi


read -p "Please enter your source profile (default: default): " SOURCE_PROFILE
SOURCE_PROFILE="${SOURCE_PROFILE=default}"

MFA_PROFILE="$SOURCE_PROFILE-mfa"

# Deffault filename values
MFA_SERIAL_FILE="${HOME}/.aws/."${SOURCE_PROFILE}"_mfaserial"
AWS_TOKEN_FILE="${HOME}/.aws/."${SOURCE_PROFILE}"_awstoken"
AWS_CREDENTIALS_PATH="${HOME}/.aws/credentials"
DURATION_SECONDS=129600

inputMFASerial() {
  aws iam list-mfa-devices --output text --profile "$SOURCE_PROFILE" | awk '{print $3}' > "${MFA_SERIAL_FILE}"
  echo "your MFA Serial has been saved"
}

getTempCredential(){
    while true; do
      read -p "Please input your 6 digit MFA Token from Authenticator App (i.e. Google Authenticator): " token
      case $token in
        [0-9][0-9][0-9][0-9][0-9][0-9] ) MFA_TOKEN=$token; break;;
        * ) echo "Please enter a valid 6 digit token" ;;
      esac
    done

authenticationOutput=$(aws sts get-session-token --serial-number "$MFA_SERIAL" --token-code "$MFA_TOKEN" --duration-seconds "$DURATION_SECONDS" --profile "$SOURCE_PROFILE" --output json)

if [ ! -z "$authenticationOutput" ]; then
  # save authentication to some file
  echo "$authenticationOutput"  > "$AWS_TOKEN_FILE"
  storeTempCredential
  echo 'profile has been updated!'
fi

}

storeTempCredential() {
  aws configure set aws_access_key_id $(cat "${AWS_TOKEN_FILE}" | jq -r .Credentials.AccessKeyId) --profile "$MFA_PROFILE"
  aws configure set aws_secret_access_key $(cat "${AWS_TOKEN_FILE}" | jq -r .Credentials.SecretAccessKey) --profile "$MFA_PROFILE"
  aws configure set aws_session_token $(cat "${AWS_TOKEN_FILE}" | jq -r .Credentials.SessionToken) --profile "$MFA_PROFILE"
  echo "Profile $MFA_PROFILE is set, now use --profile $MFA_PROFILE with AWS CLI commands"
}

if [ ! -e "${MFA_SERIAL_FILE}" ]; then
  inputMFASerial
fi

# Retrieve the serial code
MFA_SERIAL=$(cat "$MFA_SERIAL_FILE")




if [ -e "${AWS_TOKEN_FILE}" ]; then
  authenticationOuput=$(cat "${AWS_TOKEN_FILE}")
  authExpiration=$(echo "$authenticationOuput" | jq -r .Credentials.Expiration)
  nowTime=$(date -Iseconds -u)

  if [ "$authExpiration" \< "$nowTime" ]; then

    echo "Your last token has expired"
    getTempCredential
  else
    echo "Token for profile $MFA_PROFILE does not expire yet! Please add --profile $MFA_PROFILE to aws commands you want to run. Eg: aws s3 ls --profile $MFA_PROFILE"
  fi
else
  getTempCredential
fi
