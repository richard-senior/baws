#!/bin/bash

########################################################################
### LOOKUP            ##################################################
########################################################################

function findAmi {
    if [ -z "$1" ]; then
        echo "must supply filters in first parameter (ie Name=name,Values=amzn*) etc."
        return 1
    fi
    local aid="$(getAccountId)"
    local owners="$aid"
    if [ ! -z "$2" ]; then
        local owners="$2"
    fi
    #local owners="137112412989"
    #echo "aws --profile $PROFILE --region $REGION ec2 describe-images --owners $owners --filters $1 --query 'sort_by(Images, &CreationDate)[0].ImageId' --output text 2>/dev/null"
    local foo=$(aws --profile $PROFILE --region $REGION ec2 describe-images --owners $owners --filters $1 --query 'sort_by(Images, &CreationDate)[0].ImageId' --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    echo "$foo"
}


