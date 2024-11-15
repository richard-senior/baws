#!/bin/bash

# gets the accountId of the profile we're currently using
function getAccountId {
    local id=$(aws --profile $PROFILE --region $REGION sts get-caller-identity --query "Account" --output text 2>/dev/null)
    echo "$id"
}