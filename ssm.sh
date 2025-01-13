#!/bin/bash

########################################################################
### SSM            #####################################################
########################################################################

function waitForSSMConnection {
    if [ -z "$1" ]; then
        echo "you must provide the instance name or id in the first parameter"
        return 1
    fi
    local iid=$(getInstanceId "$1")
    if [ -z "$iid" ]; then
        echo "failed to get instance id for instance with name $1"
        return 1
    fi
    echo "Waiting for SSM to become available on $iid"
    timeout 300s bash <<EOF
        until aws --profile $PROFILE --region $REGION ssm get-connection-status --target $iid --query "Status" --output text; do
            sleep 10
        done
EOF
}

function sendSMALLFileViaSsm {
    if [ -z "$1" ]; then
        echo "you must send instanceId the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must send full filepath in second parameter"
        return 1
    fi
    if [ -z "$3" ]; then
        echo "you must send remote filepath in third parameter"
        return 1
    fi
    if [ ! -f "$2" ]; then
        echo "File not found!"
        return 1
    fi
    # read file and base64 it to a local variable
    local file64
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        file64=$(base64 -i "$2")
    else
        # Linux version
        file64=$(base64 -w0 "$2")
    fi

local cmds=$(cat <<-END
[
    "cd '$(dirname $3)'",
    "echo '$file64' | base64 -d > '$(basename $3)'",
    "chmod 644 '$(basename $3)'",
    "test -f '$(basename "$3")' || exit 1"
]
END
)
    sendCommand $1 "$cmds"
    return $?
}

function sendCommand {
    if [ -z "$1" ]; then
        echo "you must send the instanceId in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must command array in second parameter ie (['ls -lart'])"
        return 1
    fi

    local commandId=$(aws --profile $PROFILE --region $REGION ssm send-command \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=$2" \
        --targets "Key=instanceids,Values=$1" \
        --comment "command sent remotely" \
        --query "Command.CommandId" \
        --output text)

    if [ -z "$commandId" ]; then
        return 1
    fi

    aws --profile $PROFILE --region $REGION ssm wait command-executed \
        --command-id "$commandId" \
        --instance-id "$1"

    if [ $? != 0 ]; then
        return 1
    fi

    local result=$(aws --profile $PROFILE --region $REGION ssm get-command-invocation \
        --command-id "$commandId" \
        --instance-id "$1" \
        --output json)

    # Extract relevant information
    local status=$(echo "$result" | jq -r '.Status')
    local output=$(echo "$result" | jq -r '.StandardOutputContent')
    local error=$(echo "$result" | jq -r '.StandardErrorContent')

    if [ "$status" = "Success" ]; then
        echo "$output"
        return 0
    else
        echo "$error"
        return 1
    fi
    return 1
}

function ssmToStack {
    if [ -z "$1" ]; then
        echo "must pass instance name in the first parameter"
        return 1
    fi
    local iid=$(getInstanceId "$1")
    aws --profile $PROFILE --region $REGION ssm start-session --target $iid
}


function tunnelToInstanceOverSSM {
    if [ -z "$1" ]; then
        echo "must pass port number in first parameter"
    fi
    if [ -z "$2" ]; then
        echo "must supply instanceID in second parameter"
    fi
    aws --profile $PROFILE --region $REGION ssm start-session --target $2 \
        --document-name AWS-StartPortForwardingSession \
        --parameters "{\"portNumber\":[\"$1\"],\"localPortNumber\":[\"$1\"]}"
}

# SSH over SSM tunnel
# TODO THIS!
function sshToInstance {
    # TODO get private ip
    #local iid=$(aws --profile $PROFILE --region $REGION ec2 describe-instances --filters 'Name=tag:Name,Values=devlake' 'Name=instance-state-name,Values=running' --output text --query 'Reservations[*].Instances[*].InstanceId' 2>/dev/null)
    # ssh -i ~/.ssh/platform-services-dev.pem ssm-user@ip-10-61-255-165.$REGION.compute.internal
    # aws --profile $PROFILE --region $REGION ssm start-session --document-name AWS-StartSSHSession --target "$iid"
    sudo ssh-agent -s
    local pft=$(ssh-keygen -f "~/.ssh/known_hosts" -R "bastion-pet-servers.ps.intdigital.ee.co.uk" 2>&1)
    sudo ssh-add ~/.ssh/platform-services-dev.pem ~/.ssh/platformservices-dev.pem
    #local ip=$(getExternalIP)
    #local ip=2.29.76.117

    #ssh -Avt -o "StrictHostKeyChecking=no" ubuntu@bastion-pet-servers.ps.intdigital.ee.co.uk "ssh -o 'StrictHostKeyChecking=no' 'ec2-user@10.61.255.165'"
}
