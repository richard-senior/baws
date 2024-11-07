#!/bin/bash

source ./tags.sh

########################################################################
### VPC           ######################################################
########################################################################

function getVpcIdForPlatform {
    if [ -z "$1" ]; then
        echo "must supply platform name in first parmeter"
        return
    fi
    local ret=$(aws ec2 --profile $PROFILE --region $REGION describe-vpcs --filters "Name=tag:platform-name, Values=$1" --query "Vpcs[*].[VpcId]" --output text)
    echo "$ret"
}


function getPrivateSubnetId {
    local scheme="private"
    if [ -z "$1" ]; then
        echo "must supply index in first parmeter"
        return
    fi
    local vpcid=$(getVpcIdForPlatform $PLATFORM)
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    ret=()
    for i in $sn; do
        ret+=("$i")
    done
    echo "${ret[$1]}"
}

function getCommaDelimitedSubnetsForPlatform {
    local scheme="private"
    local vpcid=$(getVpcIdForPlatform $PLATFORM)
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    local ret=""
    for i in $sn; do
        ret="$ret$i,"
    done
    ret="${ret%?}"
    echo "$ret"
}

function getSpaceDelimitedSubnetsForPlatform {
    local scheme="private"
    local vpcid=$(getVpcIdForPlatform $PLATFORM)
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    local ret=""
    for i in $sn; do
        ret="$ret$i "
    done
    echo "$ret"
}

function getSubnetsForPlatform {
    local scheme="private"
    local vpcid=$(getVpcIdForPlatform $PLATFORM)
    # aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0099b918d2a911701 --region us-east-2 --query "Subnets[].SubnetId" --output text
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    local ret="["
    for i in $sn; do
        ret+="\"$i\","
    done
    ret="${ret%?}"
    ret+="]"
    echo "$ret"
}

function deleteDbSubnetGroup {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    if ! isDbSubnetGroupExists $1; then
        echo "DB Subnet Group '$1' does not exist. Nothing to delete."
        return
    fi
    aws --profile $PROFILE --region $REGION rds delete-db-subnet-group --db-subnet-group-name "$1"
    if [ $? -eq 0 ]; then
        echo "DB Subnet Group '$1' has been successfully deleted."
        return 0
    else
        echo "Failed to delete DB Subnet Group '$1'. It might not exist or there might be associated resources."
        return 1
    fi
}

function isDbSubnetGroupExists {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    aws --profile $PROFILE --region $REGION rds describe-db-subnet-groups --db-subnet-group-name "$1" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}
function createDbSubnetGroup {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    if isDbSubnetGroupExists $1; then
        echo "DB Subnet Group '$1' already exists. Nothing to do."
        return
    fi

    SUBNETS="$(getSubnetsForPlatform)"

    if [ -z "$SUBNETS" ]; then
        echo "No subnets found for platform '$PLATFORM'. Cannot create DB Subnet Group."
        return
    fi

    echo "Creating subnet group with subnets : $SUBNETS"
    aws --profile $PROFILE --region $REGION rds create-db-subnet-group \
        --db-subnet-group-name $1 \
        --db-subnet-group-description "Subnet group for the aurora DB that backs devlake" \
        --subnet-ids $SUBNETS \
        --tags $(getTagsRaw "$1")
}
