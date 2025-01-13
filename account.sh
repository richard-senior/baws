#!/bin/bash

# gets the accountId of the profile we're currently using
function getAccountId {
    local id=$(aws --profile $PROFILE --region $REGION sts get-caller-identity --query "Account" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$id" ]; then return 1; fi
    echo "$id"
}