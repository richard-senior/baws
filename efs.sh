#!/bin/bash

########################################################################
### EFS            #####################################################
########################################################################

function getEfsFileSystemId() {
    if [ -z "$1" ]; then
        echo "you must filesystem name in first parameter"
        return
    fi

    local file_system_id=$(aws --profile $PROFILE --region $REGION efs describe-file-systems \
        --query "FileSystems[?Name=='$1'].FileSystemId" \
        --output text)

    if [ -z "$file_system_id" ] || [ "$file_system_id" == "None" ]; then
        return 1
    else
        echo "$file_system_id"
        return 0
    fi
}

function isEfsMountPointsExists {
    if [ -z "$1" ]; then
        echo "you must filesystem name in first parameter"
        return
    fi

    local fsid=$(getEfsFileSystemId $1)
    if [ -z "$fsid" ]; then
        echo "Error: Could not retrieve EFS File System ID." >&2
        return 1
    fi

    local mount_targets=$(aws --profile $PROFILE --region $REGION efs describe-mount-targets \
        --file-system-id $fsid \
        --query 'MountTargets[*].MountTargetId' \
        --output text)

    if [ -z "$mount_targets" ]; then
        echo "No mount points exist for EFS filesystem $fsid."
        return 1
    else
        echo "Mount points exist for EFS filesystem $fsid:"
        echo "$mount_targets"
        return 0
    fi
}

function getEfsDnsName() {
    if [ -z "$1" ]; then
        echo "you must filesystem name in first parameter"
        return
    fi

    if ! checkEfsFileSystemExists $1; then
        echo "no EFS file system in place"
        return
    fi

    local file_system_id=$(getEfsFileSystemId $1)

    if [ -z "$file_system_id" ] || [ "$file_system_id" == "None" ]; then
        echo "Error: EFS filesystem '$1' not found." >&2
        return 1
    fi

    local dns_name="${file_system_id}.efs.${REGION}.amazonaws.com"

    echo "$dns_name"
}


function checkEfsFileSystemExists {
    if [ -z "$1" ]; then
        echo "you must filesystem name in first parameter"
        return
    fi

    local file_system_id=$(aws --profile $PROFILE --region $REGION efs describe-file-systems \
        --query "FileSystems[?Name=='$1'].FileSystemId" \
        --output text)

    if [ -z "$file_system_id" ] || [ "$file_system_id" == "None" ]; then
        return 1
    else
        return 0
    fi
}

function mountPointsExists {
    if [ -z "$1" ]; then
        echo "you must suplly the filesystem name in first parameter"
        return
    fi
    local fsid=$(getEfsFileSystemId "$1")
    if [ -z "$fsid" ]; then
        echo "Failed to get ID for filesystem $1"
        return 1
    fi
    local foo=$(aws --profile $PROFILE --region $REGION efs describe-mount-targets --file-system-id "$fsid" --query "MountTargets[].MountTargetId" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

function createEfsMountpoints {
    if [ -z "$1" ]; then
        echo "you must suplly the filesystem name in first parameter"
        return
    fi
    local sgname="$(getSgName $1)"
    local sgid=$(getSgId "$sgname")
    local fsid=$(getEfsFileSystemId "$1")
    local sns=$(getSpaceDelimitedSubnetsForPlatform)
    # Create mount targets for each subnet
    echo "About to create mountpoints for EFS filesystem on vpc subnets"
    for subnet in $sns; do
        echo "Creating mount target in subnet $subnet"
        aws --profile $PROFILE --region $REGION efs create-mount-target \
            --file-system-id $fsid \
            --subnet-id $subnet \
            --security-groups $sgid

        if [ $? -eq 0 ]; then
            echo "Mount target created successfully in subnet $subnet"
        else
            echo "Failed to create mount target in subnet $subnet"
            return 1
        fi
    done

    # Wait for all mount targets to become available
    echo "Waiting for all mount targets to become available..."
    aws --profile $PROFILE --region $REGION efs describe-mount-targets \
        --file-system-id $fsid \
        --query 'MountTargets[*].LifeCycleState' \
        --output text | grep -q 'creating'

    while [ $? -eq 0 ]; do
        echo "Mount targets are still being created. Waiting..."
        sleep 10
        aws --profile $PROFILE --region $REGION efs describe-mount-targets \
            --file-system-id $fsid \
            --query 'MountTargets[*].LifeCycleState' \
            --output text | grep -q 'creating'
    done

    echo "All mount targets are now available."
}

function createEfsFileSystem {
    if [ -z "$1" ]; then
        echo "must pass filesystem name in first parameter"
        return 1
    fi

    if [ -z "$2" ]; then
        echo "Optional target sg name not passed in second parameter"
        echo "Will not add ec2 connection to inbound rules of EFS sg"
    fi

    if ! checkEfsFileSystemExists "$1"; then
        local creation_token=$(uuidgen)
        echo "About to create EFS filesystem '$1'"
        local fsid=$(aws --profile $PROFILE --region $REGION efs create-file-system \
            --creation-token "$creation_token" \
            --performance-mode generalPurpose \
            --throughput-mode bursting \
            --encrypted \
            --tags Key=Name,Value="$1" Key=platform-name,Value=$PLATFORM_NAME Key=stack-name,Value=$STACK_NAME \
            --query "FileSystemId" \
            --output text
        )

        if [ $? -eq 0 ]; then
            echo "EFS File System '$1' created successfully."
        else
            echo "Failed to create EFS File System '$1'."
            return 1
        fi

        local max_attempts=30
        local attempt=0
        echo "Waiting for EFS File System to become available..."
        while [ $attempt -lt $max_attempts ]; do
            status=$(aws --profile $PROFILE --region $REGION efs describe-file-systems \
                --file-system-id "$fsid" \
                --query "FileSystems[0].LifeCycleState" \
                --output text)

            if [ "$status" == "available" ]; then
                echo "EFS File System '$1' is now available."
                break
            fi

            echo "EFS status: $status. Waiting..."
            sleep 10
            ((attempt++))
        done
    else
        echo "EFS File System '$1' already exists."
    fi

    local sgname="$1-sg"

    createSg "$sgname"
    if [ -n "$2" ]; then
        # if we know where we're going to mount this EFS
        # then add an ingress rule to the EFS SG
        local sgid=$(getSgId "$2")
        addIngressRule "$sgname" "tcp" "2049" "$2"
    fi

    createEfsMountpoints "$1"
}

function destroyEfsMounts {
    if [ -z "$1" ]; then
        echo "you must filesystem name in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION efs describe-file-systems --query "FileSystems[?Name==`$1`].FileSystemId" --output text)
    if [ ! -z "$foo" ]; then
        # remove mount targets
        local mts=$(aws --profile $PROFILE --region $REGION efs describe-mount-targets --file-system-id $foo --query "MountTargets[].MountTargetId" --output text)
        if [ ! -z "$mts" ]; then
            for mt in $mts; do
                echo "deleting mount target $mt"
                aws --profile $PROFILE --region $REGION efs delete-mount-target --mount-target-id "$mt"
            done
            echo "waiting for mountpoints to clear"
            sleep 5
        fi

        echo "deleting efs mount $foo"
        aws --profile $PROFILE --region $REGION efs delete-file-system --file-system-id "$foo"
    fi
}

function destroyEfsFileSystem {
    if ! checkEfsFileSystemExists; then
        echo "EFS File System '$EFS_NAME' does not exist. Nothing to destroy."
        return 0
    fi

    local file_system_id=$(aws --profile $PROFILE --region $REGION efs describe-file-systems \
        --query "FileSystems[?Name=='$EFS_NAME'].FileSystemId" \
        --output text)

    # Delete mount targets first
    local mount_targets=$(aws --profile $PROFILE --region $REGION efs describe-mount-targets \
        --file-system-id "$file_system_id" \
        --query "MountTargets[*].MountTargetId" \
        --output text)

    for mount_target in $mount_targets; do
        echo "Deleting mount target $mount_target..."
        aws --profile $PROFILE --region $REGION efs delete-mount-target --mount-target-id "$mount_target"
    done

    local max_attempts=30
    local attempt=0
    echo "Waiting for all mount targets of EFS File System $file_system_id to be deleted..."
    while [ $attempt -lt $max_attempts ]; do
        # Check for any remaining mount targets
        local mount_targets=$(aws --profile $PROFILE --region $REGION efs describe-mount-targets \
            --file-system-id "$file_system_id" \
            --query "MountTargets[*].MountTargetId" \
            --output text)

        if [ -z "$mount_targets" ]; then
            echo "All mount targets for EFS File System $file_system_id have been deleted."
            break
        fi

        echo "Mount targets still exist. Waiting... (Attempt $((attempt+1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done

    # Delete the file system
    echo "Deleting EFS File System '$EFS_NAME'..."
    aws --profile $PROFILE --region $REGION efs delete-file-system --file-system-id "$file_system_id"

    if [ $? -eq 0 ]; then
        echo "EFS File System '$EFS_NAME' has been successfully deleted."
    else
        echo "Failed to delete EFS File System '$EFS_NAME'."
        return 1
    fi
}