#!/bin/bash

source ./conf.sh

########################################################################
### LOADBALANCER    ####################################################
########################################################################

function isLoadBalancerExists {
    # aws --profile non-production --region $REGION elbv2 describe-load-balancers --names devlake-alb
    aws --profile $PROFILE --region $REGION elbv2 describe-load-balancers --names $lb_name 2>/dev/null
    return $?
}

function getLbArn {
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-load-balancers --names "$lb_name" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
    echo "$ret"
}

function getTargetGroupArn {
    # aws --profile non-production --region $REGION elbv2 describe-target-groups --names devlake-tg --query "TargetGroups[0].TargetGroupArn"
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names "$tg_name" --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
    echo "$ret"
}

function getListenerArn {
    local lb_arn=$(getLbArn)
    if [ -z "$lb_arn" ]; then return; fi
    # echo "aws --profile $PROFILE --region $REGION elbv2 describe-listeners --load-balancer-arn $lb_arn --query "Listeners[0].ListenerArn" --output text"
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-listeners --load-balancer-arn $lb_arn --query "Listeners[0].ListenerArn" --output text 2>/dev/null)
    if [ ! -z "$ret" ]; then
        echo "$ret"
    fi
}

function isListenerExists {
    local arn=$(getListenerArn)
    if [ -z "$arn" ]; then return 1; fi
    return 0
}

function isTargetGroupExists {
    aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names $tg_name 2>/dev/null
    return $?
}

function isTargetRegistered {
    if ! isTargetGroupExists; then return 1; fi
    local tg_arn=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names $tg_name --query 'TargetGroups[0].TargetGroupArn' --output text)
    if [ -z "$tg_arn" ]; then return 1; fi
    local instanceid=$(getInstanceId)
    aws --profile $PROFILE --region $REGION elbv2 describe-target-health --target-group-arn $tg_arn --targets Id=$instanceid >/dev/null 2>&1
    return $?
}

function deleteLoadBalancer {
    local lb_name="devlake-alb"
    local tg_name="devlake-tg"

    if isListenerExists; then
        local arn="$(getListenerArn)"
        aws --profile $PROFILE --region $REGION elbv2 delete-listener --listener-arn "$arn"
        echo "listener deleted"
    else
        echo "listener doesn't exist, skipping"
    fi

    # Delete load balancer
    if isLoadBalancerExists; then
        local lb_arn=$(getLbArn)
        echo "Deleting load balancer: $lb_arn"
        aws --profile $PROFILE --region $REGION elbv2 delete-load-balancer --load-balancer-arn $lb_arn
        # Wait for load balancer to be deleted
        aws --profile $PROFILE --region $REGION elbv2 wait load-balancers-deleted --load-balancer-arns $lb_arn
    else
        echo "Load balancer does not exist, skipping deletion"
    fi

    # Delete target group
    if isTargetGroupExists; then
        local tg_arn=$(getTargetGroupArn)
        echo "Deleting target group: $tg_arn"
        aws --profile $PROFILE --region $REGION elbv2 delete-target-group --target-group-arn $tg_arn
    else
        echo "Target group does not exist, skipping deletion"
    fi

    # Delete security group
    if isLoadBalancerSecurityGroupExists; then
        local sg_id=`getSecurityGroupId "$sg_name"`
        echo "Deleting security group: $sg_id"
        # aws --profile non-production --region $REGION ec2 delete-security-group --group-id sg-0844569a008258a24
        aws --profile $PROFILE --region $REGION ec2 delete-security-group --group-id $sg_id
    else
        echo "Security group does not exist, skipping deletion"
    fi
    echo "Load balancer cleanup complete"
}

function createLoadBalancer {
    # Check and create load balancer security group
    local subnets=$(getPublicSubnets)
    echo "SUBNETS ARE : $subnets"
    if ! isLoadBalancerSecurityGroupExists; then
        echo "load balancer SG does not exist, creating"
        if [ -z "$subnets" ]; then
            echo "Cannot find requisite subnet in the vpc"
            return 1
        fi
        local sg_id=$(aws --profile $PROFILE --region $REGION ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for $lb_name" \
            --vpc-id $VPCID \
            --tag-specifications `getTagSpecifications "security-group" "$sg_name"` \
            --query 'GroupId' \
            --output text)

        if [ -n "$sg_id" ]; then
            aws --profile $PROFILE --region $REGION ec2 authorize-security-group-ingress \
                --group-id "$sg_id" \
                --protocol tcp \
                --port 443 \
                --source-group "$sg_id"
            echo "Created security group: $sg_id"
        else
            echo "Failed to create security group"
            return 1
        fi
    else
        echo "Security group already exists"
    fi
    echo "getSgId for $sg_name"
    if [ -z "$sg_id" ]; then local sg_id=`getSecurityGroupId "$sg_name"`; fi
    # Check and create target group
    echo "Target group exists?"
    if ! isTargetGroupExists; then
        local tg_arn=$(aws --profile $PROFILE --region $REGION elbv2 create-target-group \
            --name $tg_name \
            --protocol HTTP \
            --port 4000 \
            --vpc-id $VPCID \
            --target-type instance \
            --tags `getTags "$tg_name"` \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
        echo "Created target group: $tg_arn"
    else
        echo "Target group already exists"
    fi
    if [ -z "$tg_arn" ]; then local tg_arn=$(getTargetGroupArn); fi
    echo "ALB exists?"
    # Check and create load balancer
    if ! isLoadBalancerExists; then
        local lb_arn=$(aws --profile $PROFILE --region $REGION elbv2 create-load-balancer \
            --name $lb_name \
            --subnets $subnets \
            --security-groups $sg_id \
            --tags `getTags "$lb_tags"` \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text)
        echo "Created internal load balancer: $lb_arn"
    else
        echo "Load balancer already exists"
    fi
    if [ -z "$lb_arn" ]; then local lb_arn=$(getLbArn); fi
    echo "create listener"
    # aws --profile non-production --region $REGION elbv2 create-listener --load-balancer-arn "arn:aws:elasticloadbalancing:$REGION:556428197880:loadbalancer/app/devlake-alb/68adbd20fb646681" --protocol HTTP --port 443 --default-actions Type=forward,TargetGroupArn="arn:aws:elasticloadbalancing:$REGION:556428197880:targetgroup/devlake-tg/5390d4450615aa7f"
    aws --profile $PROFILE --region $REGION elbv2 create-listener --load-balancer-arn "$lb_arn" --protocol HTTP --port 443 --default-actions Type=forward,TargetGroupArn="$tg_arn" --tags `getTags "$listener_name"`

    local iid="$(getInstanceId)"
    if [ -z "$iid" ]; then
        echo "Failed to get instance ID"
        return 1
    fi
    echo "instance id is $iid"
    # Check and register target
    if ! isTargetRegistered; then
        echo "Registering target: $iid"
        aws --profile $PROFILE --region $REGION elbv2 register-targets --target-group-arn "$tg_arn" --targets Id="$iid"
        echo "Registered target: $iid"
    else
        echo "Target already registered"
    fi

    echo "Internal load balancer setup complete"
}