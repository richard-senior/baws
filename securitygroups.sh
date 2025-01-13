#!/bin/bash

########################################################################
### SG             #####################################################
########################################################################

function isSecurityGroupId {
    if [ -z "$1" ]; then
        echo "must supply string to test in first paramter"
        return 1
    fi
    if [[ $1 =~ ^sg-[a-fA-F0-9]{17}$ ]]; then
        return 0
    fi
    return 1
}

# Find dependencies on a security group. Useful for debuging issues creating or
# destroying sg's
function listSecurityGroupDependents {
    if [ -z "$1" ]; then
        echo "you must supply an sg id in the first parameter"
        return
    fi
    aws --profile $PROFILE --region $REGION ec2 describe-instances --filters "Name=instance.group-id,Values=$1" --query 'Reservations[*].Instances[*].[InstanceId]' --output text
    aws --profile $PROFILE --region $REGION ec2 describe-security-group-references --group-id "$1" --query 'SecurityGroupReferenceSet[].ReferencingVpcId' --output text
    aws --profile $PROFILE --region $REGION ec2 describe-network-interfaces --filters "Name=group-id,Values=$1" --query 'NetworkInterfaces[*].[NetworkInterfaceId]' --output text
    aws --profile $PROFILE --region $REGION elbv2 describe-load-balancers --query "LoadBalancers[?SecurityGroups[?contains(@, '$1')]].[LoadBalancerArn]" --output text
    aws --profile $PROFILE --region $REGION rds describe-db-instances --query "DBInstances[?VpcSecurityGroups[?VpcSecurityGroupId=='$1']].[DBInstanceIdentifier]" --output text
    aws --profile $PROFILE --region $REGION elasticache describe-cache-clusters --query "CacheClusters[?SecurityGroups[?SecurityGroupId=='$1']].[CacheClusterId]" --output text
    aws --profile $PROFILE --region $REGION ec2 describe-security-groups --filters Name=ip-permission.group-id,Values=$1
    aws --profile $PROFILE --region $REGION ec2 describe-security-groups --filters Name=egress.ip-permission.group-id,Values=$1
}


# General function that checks for the existance of a security group
function isSgExists {
    if [ -z "$1" ]; then
        echo "must supply security group name in first paramter"
        return
    fi
    local vpcid=$(getVpcId)
    local sgid=$(aws --profile $PROFILE --region $REGION ec2 describe-security-groups \
        --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$vpcid" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        return 1
    fi
    if [ "$sgid" != "None" ] && [ -n "$sgid" ]; then
        return 0
    else
        return 1
    fi
}

function getSgId {
    if [ -z "$1" ]; then
        echo "must supply security group name in first paramter"
        return
    fi
    local vpcid=$(getVpcId)
    #echo "aws --profile $PROFILE --region $REGION ec2 describe-security-groups --filters \"Name=vpc-id,Values=$vpcid\" \"Name=group-name,Values=$1\" --query \"SecurityGroups[0].GroupId\" --output text 2>/dev/null"
    local foo=$(aws --profile $PROFILE --region $REGION ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpcid" "Name=group-name,Values=$1" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
    if [ -z "$foo" ]; then return 1; fi
    if [ "$foo" = "None" ]; then return 1; fi
    if [ "$foo" = "none" ]; then return 1; fi
    echo "$foo"
}

function isIngressRuleExists {
    if [ -z "$1" ]; then
        echo "must supply the security group id or name in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "must supply protocol (ie tcp) in the second parameter"
        return 1
    fi
    if [ -z "$3" ]; then
        echo "must supply port number or port range in the third parameter (ie 443 or 1-65535)"
        return 1
    fi
    if [ -z "$4" ]; then
        echo "must supply source in fourth parameter. (ie 203.0.113.0/24 or sg-1a2b3c4d etc.)"
        return 1
    fi

    local sgid=$1
    if ! isSecurityGroupId "$1"; then
        local sgid=$(getSgId "$1")
        if [ -z "$sgid" ]; then
            bawsWarn "Call to get sgid returned nothing $sgid"
            return 1
        fi
    fi
    local foo=$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-security-group-rules --filters Name="group-id",Values="$sgid" --query  --output json 2>/dev/null)
    # TODO this!
    return 1
}

function addIngressRule {
    if [ -z "$1" ]; then
        echo "must supply the security group id or name in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "must supply protocol (ie tcp) in the second parameter"
        return 1
    fi
    if [ -z "$3" ]; then
        echo "must supply port number or port range in the third parameter (ie 443 or 1-65535)"
        return 1
    fi
    if [ -z "$4" ]; then
        echo "must supply source in fourth parameter. (ie 203.0.113.0/24 or sg-1a2b3c4d etc.)"
        return 1
    fi

    # if isIngressRuleExists "$1" "$2" "$3" "$4"; then return 0; fi

    local sgid=$1
    # Check if the input is a Security Group ID (sg-xxxxxxxxxxxxxxxxx)
    if ! isSecurityGroupId "$1"; then
        sgid="$(getSgId $1)"
        if [ -z "$sgid" ]; then
            echo "Error: Unable to find Security Group with name '$1'"
            return 1
        fi
    fi
    local src=""
    # work out what we've been sent
    if isSecurityGroupId $4; then
        local src="--source-group $4"
    elif isValidCidrRange $4; then
        local src="--cidr $4"
    else
        echo "must supply a valid source in the form or a security group id or cidr range"
        return 1
    fi
    local foo=$(aws --profile $PROFILE --region $REGION ec2 authorize-security-group-ingress --group-id "$sgid" --protocol $2 --port $3 $src --query "SecurityGroupRules[0].SecurityGroupRuleId" --output text 2>/dev/null)
}

# Removes all ingress rules from the named security group
function revokeSgRules {
    #if you just want to see a list of security group rule owners then set this flag to true
    if [ -z "$1" ]; then
        echo "must supply the security group id or name in the first parameter"
        return 1
    fi

    local sgid=$1
    # Check if the input is a Security Group ID (sg-xxxxxxxxxxxxxxxxx)
    if [ ! [ $1 =~ ^sg-[a-fA-F0-9]{17}$ ]]; then
        sgid="$(getSgId $1)"
        if [ -z "$sgid" ]; then
            echo "Error: Unable to find Security Group with name '$1'"
            return 1
        else
            echo "$1 has ID $sgid"
        fi
    fi

    local foo=$(aws --profile "$PROFILE" --region "$REGION" ec2 describe-security-group-rules --filters Name="group-id",Values="$sgid" --query "SecurityGroupRules[?IsEgress == \`false\`].[SecurityGroupRuleId]" --output text)
    for id in $foo; do
        res=$(aws --profile "$PROFILE" --region "$REGION" ec2 revoke-security-group-ingress --group-id $sgid --security-group-rule-ids $id)
        if [ $? -eq 0 ]; then
            echo "Revoked rule $id"
        else
            echo "Failed to revoke rule $id"
            echo "$res"
        fi
    done
}

function createSg {
    if [ -z "$1" ]; then
        echo "must supply the security group name in the first parameter"
        return 1
    fi
    if isSgExists "$1"; then
        echo "SG $1 already exists"
        return 0
    fi
    local desc="Security Group for $1"
    if [ -z "$PROJECT_DESCRIPTION" ]; then
        local desc="$PROJECT_DESCRIPTION"
    fi

    echo "Creating security group with name $1"
    local vpcid=$(getVpcId)
    local tagSpecs="$(getTagSpecificationsNoQuotes $1 'security-group')"
    local foo=$(aws --profile $PROFILE --region $REGION ec2 create-security-group --description "$desc" --vpc-id $vpcid --group-name $1 --tag-specification $tagSpecs --query 'GroupId' --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        bawsWarn "Failed to create security group $1 - Non-zero return"
        return 1
    fi
    if [ -z "$foo" ]; then
        echo "aws --profile $PROFILE --region $REGION ec2 create-security-group --description \"$desc\" --vpc-id $vpcid --group-name $1 --tag-specification $tagSpecs --query 'GroupId' --output text 2>/dev/null"
        bawsWarn "Failed to create security group $1 - empty response"
        return 1
    fi
    if ! isSecurityGroupId "$foo"; then
        echo "Failed to create Security Group $1 - response was not a security group id [$foo]"
        return 1
    fi
    echo "Security group $1 created with id $foo"
    return 0
}

function deleteSg {
    if [ -z "$1" ]; then
        echo "must supply the security group name in the first parameter"
        return 1
    fi
    if ! isSgExists $1 ; then
        echo "Security Group $1 does not exist. No need to delete it"
        return
    fi

    echo "about to delete Security Group $1"
    local id=$(getSgId $1)

    if [ -z "$id" ]; then return; fi
        # removeSgRules "$id"
        local foo=$(aws --profile "$PROFILE" --region "$REGION" ec2 delete-security-group --group-id "$id" 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "Security group '$1' deleted successfully."
        else
            echo "Failed to delete security group '$1'."
            return 1
    fi
}

function getUnusedSecurityGroups {
  #majical join query finds unused security groups
  local foo=`comm -23  <(aws ec2 --profile $PROFILE --region $REGION describe-security-groups --query 'SecurityGroups[*].GroupId'  --output text | tr '\t' '\n'| sort) <(aws ec2 --profile $PROFILE --region $REGION describe-instances --query 'Reservations[*].Instances[*].SecurityGroups[*].GroupId' --output text | tr '\t' '\n' | sort | uniq)`
  echo "$foo"
}