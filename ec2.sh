#!/bin/bash

source ./conf.sh

########################################################################
### EC2            #####################################################
########################################################################

function getInstanceId {
    instanceid=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --filters "Name=tag:Name,Values=$STACKNAME" "Name=vpc-id, Values=$VPCID"  "Name=tag:environment-name, Values=$environment" --query "Reservations[].Instances[?State.Name=='running'][].InstanceId" --output text 2>/dev/null)
    # If we still don't have an instance ID, print an error message
    if [ -z "$instanceid" ]; then
        return 1
    fi
    # Print the instance ID
    echo "$instanceid"
}

function getInstancePrivateIp {
    if [ -z "$1" ]; then
        echo "you must supply the instanceID in the first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $1 --output text --query 'Reservations[*].Instances[*].PrivateIpAddress' 2>/dev/null)
    if [ -z "$foo" ]; then
        echo "no instance found with id $1"
        return
    fi
    echo $foo
}

function isInstanceExists {
    echo "TODO this"
    local iid=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --filters "Name=name,Values=$STACK" "Name=tag:Name,Values=$STACK" "Name=tag:platform-name,Values=${PLATFORM}" "Name=tag:environment-name,Values=${ENVIRONMENT}" --output text --query 'Reservations[*].Instances[*].InstanceId' 2>/dev/null)
}

function createInstance {
    if [ -z "$AMIID" ]; then
        echo "You first create an environment variable named 'AMIID' which contains the ID of the AMI to use when running this instance"
        return 1
    fi
    if [ -z "$INSTANCETYPE" ]; then
        echo "You first create an environment variable named 'INSTANCETYPE' which contains type of instance to use ie. t3a.medium etc."
        return 1
    fi
    if [ -z "$SNIDS" ]; then
        echo "You first create an environment variable named 'SNIDS' which contains a space delimited list of security group id's to associate with this instance"
        echo "These will likely be the private or public security groups of your VPC. see baws/VPC and baws/securitygroups"
        return 1
    fi
    if [ -z "$SGIDS" ]; then
        echo "You first create an environment variable named 'SGIDS' which contains a space delimited list of security group id's to associate with this instance"
        echo "These will likely be the private or public security groups of your VPC. see baws/VPC and baws/securitygroups"
        return 1
    fi

    echo "require,  subnet ids, tag-specifications"

    if [ -z "$iid" ]; then
        echo "Creating instance"
        echo "aws --profile $PROFILE --region $REGION ec2 run-instances --image-id \"$AMIID\" --count 1 --key-name \"platform-services-dev\" --instance-type \"$INSTANCETYPE\" --security-group-ids \"$dslgid\" --subnet-id \"$snids\" --tag-specifications \"$(getTagSpecifications 'instance')\" --query \"Instances[0].InstanceId\" --output text"
        # create it
        local iid=$(aws --profile $PROFILE --region $REGION ec2 run-instances --image-id "$AMIID" --count 1 --key-name "platform-services-dev" --instance-type "$INSTANCETYPE" --security-group-ids "$dslgid" --subnet-id "$snids" --tag-specifications "$(getTagSpecifications 'instance')" --query "Instances[0].InstanceId" --output text)
        echo "Created instance $iid"
        while STATE=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --instance-ids $iid --output text --query 'Reservations[*].Instances[*].State.Name'); test "$STATE" != "running"; do
            sleep 1;
        done
        echo "associate instance profile with instance"
        #aws --profile npt --region $REGION ec2 associate-iam-instance-profile --instance-id i-0fde1379136afb238 --iam-instance-profile Name=devlake-instance-profile
        aws --profile $PROFILE --region $REGION ec2 associate-iam-instance-profile --instance-id $iid --iam-instance-profile Name=$n
    else
        echo "Found instance with id $iid"
    fi
}

