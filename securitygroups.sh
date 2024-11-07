#!/bin/bash

source ./conf.sh

########################################################################
### SG             #####################################################
########################################################################

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
    local sg_id=$(aws --profile $PROFILE --region $REGION ec2 describe-security-groups \
        --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPCID" \
        --query "SecurityGroups[0].GroupId" \
        --output text)

    if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
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
    local foo=$(aws --profile $PROFILE --region $REGION ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPCID" "Name=group-name,Values=$1" --output json 2>/dev/null)
    if [ ! -z "$foo" ]; then
        local ret=$(echo "$foo" | jq -r ".SecurityGroups[0].GroupId")
        if [ ! -z "$ret" ] && [ "$ret" != "null" ]; then
            echo "$ret"
            return
        fi
    fi
    echo ""
}

# Removes all ingress rules from the named security group
function removeSgRules {
    #if you just want to see a list of security group rule owners then set this flag to true
    if [ -z "$1" ]; then
        echo "must supply the security group id or name in the first parameter"
        return 1
    fi

    local sgid=$1
    # Check if the input is a Security Group ID (sg-xxxxxxxxxxxxxxxxx)
    if [[ $1 =~ ^sg-[a-fA-F0-9]{17}$ ]]; then
        echo "Was passed an SGID not an SGName.. proceeding with $1"
    else
        echo "Was passed an SG Name, not an id looking up ID for $1"
        sgid="$(getSgId $1)"
        if [ "$sgid" == "None" ] || [ -z "$sgid" ]; then
            echo "Error: Unable to find Security Group with name '$1'"
            return 1
        else
            echo "$1 has ID $sgid"
        fi
    fi
    echo "removing inbound rules for $sgid"

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
        removeSgRules "$id"
        aws --profile "$PROFILE" --region "$REGION" ec2 delete-security-group --group-id "$id"
        if [ $? -eq 0 ]; then
            echo "Security group '$1' deleted successfully."
        else
            echo "Failed to delete security group '$1'."
            return 1
    fi
}