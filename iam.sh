#!/bin/bash

function isUserAdmin {
  if [ -z "$1" ]; then
    echo "must supply username in first parameter"
    return 1
  fi
  local foo=$(aws --profile $PROFILE --region $REGION iam list-groups-for-user --user-name $1 --query "Groups[].GroupName" --output text)
  if [ -z "$1" ]; then
    return 1
  fi
  for i in $foo; do
    if [ "$i" == "admin" ]; then
      return 0
    fi
  done
  return 1
}

function getNonProdIamToken {
    # Check if the credentials file exists and if the token is still valid
    if [ ! -f ~/.aws/credentials ] || ! grep -q '\[npt\]' ~/.aws/credentials; then
        echo "Credentials file or profile 'npt' not found. Obtaining new token."
        return
    fi

    # Check if we have a valid token already
    local token_expiration="$(aws configure get expiration --profile npt 2>/dev/null)"
    local now="$(date '+%Y-%m-%dT%H:%M:%S')"
    if [[ -n "$token_expiration" && "$token_expiration" > "$now" ]]; then
        echo "Using existing session token (expires $token_expiration)"
        return
    else
        echo "Existing session token expired ($token_expiration - $now) or not found. Obtaining new token."
    fi

    # If we've reached here, we need to get a new token
    read -p "Please enter your Google Authenticator OTP: " otp

    if [ -z "$otp" ]; then
        echo "you must supply a google auth otp code in the first parameter"
        return
    fi

    #local arn="arn:aws:iam::556428197880:role/Full-Admin"
    local arn="arn:aws:iam::556428197880:mfa/richard.senior"
    local credentials=$(aws --profile non-production sts get-session-token --serial-number "$arn" --token-code "$otp" --duration-seconds 43200)

    if [ $? -ne 0 ]; then
        echo "Failed to get session token."
        return 1
    fi

    local accessKeyId=$(echo "$credentials" | jq -r '.Credentials.AccessKeyId')
    local secretKey=$(echo "$credentials" | jq -r '.Credentials.SecretAccessKey')
    local token=$(echo "$credentials" | jq -r '.Credentials.SessionToken')
    local expiration=$(echo "$credentials" | jq -r '.Credentials.Expiration')

    aws configure set aws_access_key_id "$accessKeyId" --profile npt
    aws configure set aws_secret_access_key "$secretKey" --profile npt
    aws configure set aws_session_token "$token" --profile npt
    aws configure set expiration "$expiration" --profile npt
    aws configure set region eu-west-1 --profile npt

    echo "New session token obtained and configured for profile 'npt'. Expires at $expiration."
    return 0
}