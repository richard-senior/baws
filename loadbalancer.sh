#!/bin/bash

########################################################################
### LOADBALANCER    ####################################################
########################################################################

function isLoadBalancerExists {
    if [ -z "$1" ]; then
        echo "you must supply loadbalancer name in the first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 describe-load-balancers --names $1 --query "LoadBalancerDescriptions[0].LoadBalancerName" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

function getLbArn {
    if [ -z "$1" ]; then
        echo "you must supply loadbalancer name in the first parameter"
        return
    fi
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-load-balancers --names "$1" --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
    echo "$ret"
}

function destroyLoadBalancer {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if isListenerExists "$1"; then
        destroyListener "$1"
    else
        echo "listener doesn't exist, skipping"
    fi

    # Delete target group
    if isTargetGroupExists "$1"; then
        destroyTargetGroup "$1"
    else
        echo "Target group for $1 does not exist, skipping deletion"
    fi

    # Delete load balancer
    if isLoadBalancerExists "$1"; then
        local lb_arn=$(getLbArn "$1")
        if [ $? -ne 0 ]; then
            echo "Failed to determine the ARN of the loadbalancer"
            return 1;
        fi
        echo "Deleting load balancer: $lb_arn"
        local foo=$(aws --profile $PROFILE --region $REGION elbv2 delete-load-balancer --load-balancer-arn $lb_arn 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "call to delete load balancer failed"
            return 1
        fi
        # Wait for load balancer to be deleted
        aws --profile $PROFILE --region $REGION elbv2 wait load-balancers-deleted --load-balancer-arns $lb_arn
    fi

    local sgname="$1-sg"
    # Delete security group
    if isSgExists "$sgname"; then
        deleteSg "$sgname"
        if [ $? -ne 0 ]; then
            echo "Failed to delete security group $sgname"
            return 1
        fi
    else
        echo "Security group $sgname does not exist, skipping deletion"
    fi
    echo "Load balancer cleanup complete"
}

function createLoadBalancer {

    if [ -z "$1" ]; then
        echo "must supply LB name in the first parameter"
        return 1
    fi

    local sgname="$1-sg"
    if ! isSgExists "$sgname"; then
        echo "load balancer security group does not exist, creating"
        createSg "$sgname"
        if [ $? -ne 0 ]; then
            echo "Failed to create security $sgname"
            return 1
        fi
    else
        echo "load balancer security group $sgname exists"
    fi

    local sgid=$(getSgId "$sgname")
    if [ $? -ne 0 ]; then
        echo "Failed to get security group id for $sgname"
        return 1
    fi
    if [ -z "$sgid" ]; then
        echo "Failed to get security group id for $sgname"
        return 1;
    fi
    echo "security group id: $sgid"

    local subnets=$(getSubnetsForPlatform 'public')
    if [ -z "$subnets" ]; then
        echo "Cannot find requisite subnet in the vpc"
        return 1
    fi

    # target group
    local tgname="$1-tg"
    local tgarn=""
    if ! isTargetGroupExists "$1"; then
        createTargetGroup "$1"
        if [ $? -ne 0 ]; then
            echo "Failed to create target group"
            return 1
        fi
    else
        echo "target group $tgname exists"
    fi

    local tgarn=$(getTargetGroupArn "$1");
    if [ $? -ne 0 ]; then
        echo "Failed to get target group ARN"
        return 1
    fi
    if [ -z "$tgarn" ]; then
        echo "Failed to get target group ARN"
        return 1
    fi

    local lbarn=""
    # Check and create load balancer
    if ! isLoadBalancerExists "$1"; then
        local lbarn=$(aws --profile $PROFILE --region $REGION elbv2 create-load-balancer \
            --name $1 \
            --subnets $subnets \
            --security-groups $sgid \
            --tags $(getTags "$1") \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to create loadbalancer"
            return 1
        fi
        if [ -z "$lbarn" ]; then
            echo "failed to create loadbalancer"
            return 1
        fi
    else
        echo "loadbalancer $1 exists"
    fi

    if [ -z "$lbarn" ]; then
        local lbarn=$(getLbArn "$1")
    fi
    if [ $? -ne 0 ]; then
        echo "failed to get loadbalancer arn"
        return 1
    fi
    if [ -z "$lbarn" ]; then
        echo "failed to get loadbanacer arn"
        return 1
    fi

    # listener
    if ! isListenerExists "$1"; then
        echo "Creating listener"
        createListener "$1"
        if [ $? -ne 0 ]; then
            echo "failed to create listener for lb $1"
            return 1
        fi
    else
        echo "listener for $1 created"
    fi
}

########################################################################
### TARGET GROUPS    ###################################################
########################################################################

function isTargetGroupExists {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    local tgname="$1-tg"
    #echo "aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names $tgname"
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names $tgname 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

function getTargetGroupArn {
    if [ -z "$1" ]; then
        echo "you must supply load balancer name in the first parameter"
        return
    fi
    local tgname="$1-tg"
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names "$tgname" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$ret" ]; then return 1; fi
    echo "$ret"
    return 0
}

function destroyTargetGroup {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if ! isTargetGroupExists "$1"; then
        echo "target group for $1 does not exist, skipping"
        return 0
    fi
    local tgname="$1-tg"
    local tgarn=$(getTargetGroupArn "$1")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$tgarn" ]; then return 1; fi
    echo "Deleting target group: $tgarn"
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 delete-target-group --target-group-arn $tgarn 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to delete target group: $tgarn"
        return 1
    fi
    return 0
}

function createTargetGroup {
    if [ -z "$1" ]; then
        echo "you must supply load balancer name in the first parameter"
        return 0
    fi

    local tgname="$1-tg"
    echo "target group does not exist, creating"
    local tgarn=$(aws --profile $PROFILE --region $REGION elbv2 create-target-group \
        --name $tgname \
        --protocol HTTP \
        --port 4000 \
        --vpc-id $(getVpcId) \
        --target-type instance \
        --tags $(getTags $tgname) \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "Failed to create target group"
        return 1
    fi
    if [ -z "$tgarn" ]; then
        echo "Failed to create target group"
        return 1;
    fi

    # wait target-in-service may work here but just sleep
    sleep 5
    echo "Target group $tgname created with arn $tgarn"
    return 0
}

function isTargetRegistered {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if [ -z "$2" ]; then
        echo "you must supply instance name or id in the second parameter"
        return
    fi
    if ! isTargetGroupExists "$1"; then return 1; fi
    local tgname="$1-tg"
    local tg_arn=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-groups --names $tgname --query 'TargetGroups[0].TargetGroupArn' --output text)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$tg_arn" ]; then return 1; fi
    local instanceid=$(getInstanceId "$2")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$instanceid" ]; then return 1; fi
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 describe-target-health --target-group-arn $instanceid --targets Id=$2 >/dev/null 2>&1)
    if [ $? -ne 0 ]; then return 1; fi
    return 0
}

function registerTarget {

    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if [ -z "$2" ]; then
        echo "you must supply instance name in the second parameter"
        return
    fi

    local tgarn=$(getTargetGroupArn "$1")
    local iid=$(getInstanceId "$2")

    # Check and register target
    if ! isTargetRegistered "$1" "$iid"; then
        echo "Registering target: $iid on $tgarn"
        local foo=$(aws --profile $PROFILE --region $REGION elbv2 register-targets --target-group-arn "$tgarn" --targets Id="$iid" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to register instance $1 on target group $tgarn"
            return 1
        fi
        echo "Registered target: $iid on $tgarn"
    else
        echo "Target $iid already registered on $tgarn"
    fi

    # make sure there's an ingress rule on the ec2 security group for the load balancer
    local ec="$2-sg"
    local lb="$1-sg"
    echo "Ensuring EC2 SG ingress allows LoadBalancer traffic from $lb to $ec on port 443"
    local ecid=$(getSgId "$ec")
    local lbid=$(getSgId "$lb")
    addIngressRule "$ecid" "tcp" "443" "$lbid"
}

function deregisterTarget {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if [ -z "$2" ]; then
        echo "you must supply instance name in the second parameter"
        return
    fi

    local tgarn=$(getTargetGroupArn "$1")
    local iid=$(getInstanceId "$2")

    # Check and register target
    if isTargetRegistered "$1" "$iid"; then
        echo "Deregistering target: $iid on $tgarn"
        local foo=$(aws --profile $PROFILE --region $REGION elbv2 deregister-targets --target-group-arn "$tgarn" --targets Id="$iid" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to deregister instance $1 on target group $tgarn"
            return 1
        fi
        echo "Deregistered target: $iid on $tgarn"
    else
        echo "Target $iid already deregistered on $tgarn"
    fi
}

########################################################################
### LISTENERS    #######################################################
########################################################################

function isListenerExists {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    local arn=$(getListenerArn "$1")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$arn" ]; then return 1; fi
    return 0
}

function getListenerArn {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    local lb_arn=$(getLbArn "$1")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$lb_arn" ]; then return 1; fi
    # echo "aws --profile $PROFILE --region $REGION elbv2 describe-listeners --load-balancer-arn $lb_arn --query "Listeners[0].ListenerArn" --output text"
    local ret=$(aws --profile $PROFILE --region $REGION elbv2 describe-listeners --load-balancer-arn $lb_arn --query "Listeners[0].ListenerArn" --output text 2>/dev/null)
    if [ -z "$ret" ]; then return 1; fi
    echo "$ret"
}

function destroyListener {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi
    if ! isListenerExists "$1"; then
        echo "listener does not exist, skipping"
        return 0
    fi
    local arn=$(getListenerArn "$1")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$arn" ]; then return 1; fi
    echo "Deleting listener: $arn"
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 delete-listener --listener-arn $arn 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to delete listener: $arn"
        return 1
    fi
    return 0
}

function createListener {
    if [ -z "$1" ]; then
        echo "you must supply the loadbalancer name in the first parameter"
        return
    fi

    if isListenerExists ""; then
        echo "listener already exist"
        return 0
    fi

    echo "Creating listener"
    local foo=$(aws --profile $PROFILE --region $REGION elbv2 create-listener \
        --load-balancer-arn "$lbarn" \
        --protocol HTTP \
        --port 443 \
        --default-actions Type=forward,TargetGroupArn="$tgarn" \
        --tags `getTags "$1"` 2>/dev/null)
}