#!/bin/bash

########################################################################
### EC2            #####################################################
########################################################################

# Gets instance id for instance name
function getInstanceId {
    if [ -z "$1" ]; then
        echo "you must supply the instance name (or id) in the first parameter"
        return
    fi

    # were we passed an ID anyway?
    if [[ $1 =~ ^i-[a-fA-F0-9]*$ ]]; then
        echo "$1"
        return 0
    fi

    local iid=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --filters "Name=tag:Name,Values=$1" "Name=vpc-id, Values=$VPCID"  "Name=tag:environment-name, Values=$ENVIRONMENT" --query "Reservations[].Instances[?State.Name=='running'][].InstanceId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$iid" ]; then return 1; fi
    echo "$iid"
    return 0
}

function getInstancePrivateIp {
    if [ -z "$1" ]; then
        echo "you must supply the instanceID in the first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $1 --output text --query 'Reservations[*].Instances[*].PrivateIpAddress' 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    echo $foo
    return 0
}

function isInstanceExists {
    if [ -z "$1" ]; then
        echo "you must supply the instance name in the first parameter"
        return
    fi
    local iid=$(getInstanceId "$1")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$iid" ]; then return 1; fi
    return 0
}

function createInstance {
    # creates an EC2 instance in the private subnets of the VPC
    # name provided in $1
    # AMI ID provided in $2
    # instance type provided in $3
    # creates a security group (if not exists) with a name derived from $1
    # adds ingress rules for all ports for everything in the VPC cidr range
    # places the instance on the private subnets of the VPC
    if [ -z "$1" ]; then
        echo "you must supply the instance name in the first parameter (ie my-ec2-test-instance)"
        return
    fi
    if [ -z "$2" ]; then
        echo "You must pass AMIID in the second parameter (ie ami-0ba84a789d6f9e519)"
        return 1
    fi
    if [ -z "$3" ]; then
        echo "You must pass instance type in the third parameter (ie t3a.medium)"
        return 1
    fi
    local AMIID="$2"
    local INSTANCETYPE="$3"

    # ok calculate the security group name from $1
    local name="$1-sg"
    if ! isSgExists "$name"; then
        echo "Security group $name does not exist.. creating"
        createSg "$name"
        if [ $? -ne 0 ]; then
            echo "Failed to create security group for instance $1"
            return 1
        fi
        sleep 5
    else
        echo "instance security group $name already exists"
    fi
    # we can't really check if a rule exists on an SG
    # add ingress rules for vpc
    cr=$(getVpcCidrRange)
    if [ $? -ne 0 ]; then
        echo "Failed find VPC cidr range"
        return 1
    fi
    addIngressRule "$name" "tcp" "1-65535" "$cr"
    if [ $? -ne 0 ]; then
        echo "Failed to add ingress rule for VPC to security group with name $name"
        return 1
    fi

    # Also create an instance profile if this doesn't exist
    local ROLENAME="$1-instanceprofile"
    local SGIDS=$(getSgId "$name")
    if [ $? -ne 0 ]; then
        echo "Failed to get security group id for $name"
        return 1
    fi
    # now get the private subnet id's of the VPC
    local SNID=$(getSubnet)
    if [ $? -ne 0 ]; then
        echo "Failed to get a private subnet id for VPC"
        return 1
    fi

    if ! isInstanceExists "$1"; then
        # create it
        echo "Creating EC2 instance with name $1"
        local iid=$(aws --profile $PROFILE --region $REGION ec2 run-instances --image-id "$AMIID" --count 1 --key-name "platform-services-dev" --instance-type "$INSTANCETYPE" --security-group-ids "$SGIDS" --subnet-id "$SNID" --tag-specifications "$(getTagSpecificationsJson "$1" 'instance')" --query "Instances[0].InstanceId" --output text)
        if [ $? -ne 0 ]; then
            bawsWarn "Failed to create EC2 Instance"
            return 1
        fi
        if [ -z "$iid" ]; then
            echo "ec2 run-instances did not return an iid"
            return 1
        fi
        echo "Awaiting instance creation..."
        aws --profile $PROFILE --region $REGION ec2 wait instance-running --instance-ids "$iid"
        if [ $? -ne 0 ]; then
            echo "Instance creation failed.."
            return 1
        fi
        echo "Instance created with iid: $iid You should now associate instance profiles etc."
    else
        local iid=$(getInstanceId "$1")
        echo "Instance with id $iid already exists"
    fi
}

function destroyInstance {
    if [ -z "$1" ]; then
        echo "you must supply the instance name in the first parameter (ie my-ec2-test-instance)"
        return
    fi
    if ! isInstanceExists "$1"; then
        echo "Instance $1 does not exist"
    else
        local iid=$(getInstanceId "$1")
        if [ $? -ne 0 ]; then
            echo "Failed to get instance id for instance $1"
            return 1
        fi

        echo "Terminating instance $1 with iid $iid"
        aws --profile $PROFILE --region $REGION ec2 terminate-instances --instance-ids "$iid" --output text 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to terminate instance $1"
            return 1
        fi
        echo "Awaiting instance termination..."
        aws --profile $PROFILE --region $REGION ec2 wait instance-terminated --instance-ids "$iid" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "Failed to wait for instance $1 to terminate"
            return 1
        fi
        echo "Instance terminated"
    fi

    local name="$1-sg"
    if isSgExists "$name"; then
        echo "removing associated security group $name"
        deleteSg "$name"
        if [ $? -ne 0 ]; then
            echo "Failed to create security group for instance $1"
            return 1
        fi
    else
        echo "Security group $name does not exist"
    fi
}


