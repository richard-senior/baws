#!/bin/bash

source ./conf.sh

########################################################################
### ROLE           #####################################################
########################################################################

function getRoleId {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" --query "Role.RoleId" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
    fi
}

function getRoleName {
    if [ -z "$1" ]; then
        echo "you must role id in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION iam list-roles --query "Roles[?RoleId==$1].RoleName" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
    fi
}

function getRoleArn {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" --query "Role.Arn" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
    fi
}

function roleExists {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    if aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function deleteRole {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    if ! roleExists "$1"; then
        echo "role $1 does not exist. No need to delete it"
        return
    fi

    local n="$1"
    local foo=$(aws --profile ${PROFILE} --region ${REGION} iam get-instance-profile --instance-profile-name "$n" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ ! -z "$foo" ]; then
        echo "deleting instance profile $foo"
        aws --profile $PROFILE --region $REGION iam remove-role-from-instance-profile --instance-profile-name "$n" --role-name "$n"
        aws --profile $PROFILE --region $REGION iam delete-instance-profile --instance-profile-name "$n"
    fi

    local rid=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$n" --query "Role.RoleId" --output text)
    if [ -z "$rid" ]; then
        echo "no role found with name $n"
        return
    else
        echo "Found role with id $rid"
    fi

    #attached policies
    echo "finding attached policies"
    local POLICIES=$(aws --profile $PROFILE --region $REGION iam list-attached-role-policies --role-name $n --query "AttachedPolicies[].PolicyArn" --output text)
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            local ATTACHMENT_COUNT=$(aws --profile $PROFILE --region $REGION iam get-policy --policy-arn $POLICY --query "Policy.AttachmentCount" --output text)
            echo "detaching $POLICY from $n"
            aws --profile $PROFILE iam detach-role-policy --role-name $n --policy-arn $POLICY
            if [ 1 == $ATTACHMENT_COUNT ]; then
                echo "Policy is only attached to $ATTACHMENT_COUNT roles, deleting it."
                aws --profile $PROFILE iam delete-policy --policy-arn $POLICY
            else
                echo "Detatch but don't delete policy because it's attached to $ATTACHMENT_COUNT roles"
            fi
        done
    else
        echo "Found no attached policies"
    fi

    #Inline policies
    echo "Finding inline policies"
    local POLICIES=$(aws --profile $PROFILE iam list-role-policies --role-name $n --query "PolicyNames[]" --output text)
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            aws --profile $PROFILE iam delete-role-policy --role-name $n --policy-name $POLICY
        done
    else
     echo "Found no inline policies"
    fi

    echo "Deleting role $n"
    aws --profile $PROFILE --region $REGION iam delete-role --role-name "$n"
}

function createPolicy {
    echo "TODO THIS!"
}

function createRole {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    if [ -z "$2" ]; then
        echo "you must service type in second parameter (ie rds.amazonaws.com or ec2.amazonaws.com etc.)"
        echo "this is used to create the trust policy"
        echo "you may also pass something like: \"AWS\": [\"arn:aws:iam::<AccountBId>:role/<AccountBRole>\",  \"arn:aws:iam:: <AccountCId>:role/<AccountCRole>\"] etc."
        echo "TODO that last part is a lie, currently"
        return
    fi
    if roleExists "$1"; then
        echo "IAM role '$1' already exists."
        return
    fi

    echo "Creating IAM role $1"
    # Create the IAM role
    aws --profile $PROFILE --region $REGION iam create-role \
        --role-name "$1" \
        --assume-role-policy-document "{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"$2\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }"
}

function deleteInstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE --region $REGION iam delete-instance-profile --instance-profile-name $1 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "deleted instance profile $1"
    else
        echo "problem deleting instance profile $1"
    fi
}


# Creates an instance profile and adds a role to it
# You can create the role first (it must have the same name)
# or this function will create a role and leave it blank
# You can then populate the role later using the above functions
function createInstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
        return
    fi
    # if the instance profile exists just return its id
    local foo=$(aws --profile $PROFILE --region $REGION iam get-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ ! -z "$foo" ]; then
        echo "$foo"
        return
    fi
    # create it
    local ipid=$(aws --profile $PROFILE --region $REGION iam create-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text)
    # Now check if the role on which it is based exists
    local rid=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" --query "Role.RoleId" --output text 2>/dev/null)
    if [ -z "$rid" ]; then
        #create the role
        local rid=$(aws --profile $PROFILE --region $REGION iam create-role --role-name "$1" --assume-role-policy-document "$trust" --query 'Role.Arn' --output text)
        # attach ssm policies
        aws --profile $PROFILE --region $REGION iam attach-role-policy --role-name "$1" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        aws --profile $PROFILE --region $REGION iam attach-role-policy --role-name "$1" --policy-arn arn:aws:iam::aws:policy/AmazonSSMPatchAssociation
        aws --profile $PROFILE --region $REGION iam attach-role-policy --role-name "$1" --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess
    fi
    # attach role to instance profile
    aws --profile $PROFILE --region $REGION iam add-role-to-instance-profile --instance-profile-name "$1" --role-name "$1"
    echo "$ipid"
}
