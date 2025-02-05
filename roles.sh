#!/bin/bash

########################################################################
### POLICIES           #################################################
########################################################################


function policyExists {
    if [ -z "$1" ]; then
        echo "you must supply the policy name or id in the first parameter"
        return 1
    fi
    local id=$(aws --profile $PROFILE iam list-policies --query "Policies[?PolicyName=='$1'].PolicyId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$id" ]; then return 1; fi
    return 0
}

# Gets the arn of the given policy (name supplied in first parameter) if
# the policy exists. Otherwise returns nothing
function getPolicyArn {
    if [ -z "$1" ]; then
        echo "you must supply the policy name or id in the first parameter"
        return 1
    fi
    local arn=$(aws --profile $PROFILE iam list-policies --query "Policies[?PolicyName=='$1'].Arn" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$arn" ]; then return 1; fi
    echo "$arn"
    return 0
}

function calculatePolicyArn {
    if [ -z "$1" ]; then
        echo "you must supply the policy name the first parameter"
        return 1
    fi
    echo "arn:aws:iam:::policy/$1"
}

#### policies
function createTrustPolicy {
    if [ -z "$1" ]; then
        echo "you must supply the service in the first parameter (ie ec2.amazonaws.com)"
        return 1
    fi
trust=$(cat <<-END
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "$1"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
END
)
    echo "$trust"
}

function createPolicy {
    echo "TODO THIS!"
    echo "add tags if possible"
}

function isManagedPolicyOnRole {
    if [ -z "$1" ]; then
        echo "you must supply the role name on which you want the policy attaching in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must supply the aws policy arn in the second parameter (ie arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore)"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam list-attached-role-policies --role-name "$1" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to list policies on role with name $1"
        return 1
    fi
    if [ -z "$foo" ]; then
        echo "Failed to list policies on role with name $1"
        return 1
    fi
    for pa in "$foo"; do
        if [ "$pa" = "$2" ]; then
            return 0;
        fi
    done
    return 1
}

function attachManagedPolicyToRole {
    if [ -z "$1" ]; then
        echo "you must supply the role name on which you want the policy attaching in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must supply the aws policy arn in the second parameter (ie arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore)"
        return 1
    fi

    if isManagedPolicyOnRole "$1" "$2"; then
        echo "policy $2 already attached to role $1"
        return 0
    fi

    local rid=$(getRoleId "$1")
    if [ -z "$rid" ]; then
        echo "role $1 does not exist"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam attach-role-policy --role-name "$1" --policy-arn $2 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "policy $2 attached to role $1"
        return 0
    fi
    return 1
}

########################################################################
### ROLES           ####################################################
########################################################################

function getRoleId {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return
    fi
    local foo=$(aws --profile $PROFILE iam get-role --role-name "$1" --query "Role.RoleId" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
        return 0
    fi
    return 1
}

function getRoleName {
    if [ -z "$1" ]; then
        echo "you must role id in first parameter"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam list-roles --query "Roles[?RoleId==$1].RoleName" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
        return 0
    fi
    return 1
}

function getRoleArn {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam get-role --role-name "$1" --query "Role.Arn" --output text 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$foo"
        return 0
    fi
    return 1
}

function roleExists {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return 1
    fi
    if aws --profile $PROFILE iam get-role --role-name "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

function deleteRole {
    if [ -z "$1" ]; then
        echo "you must role name in first parameter"
        return 1
    fi
    if ! roleExists "$1"; then
        echo "role $1 does not exist. No need to delete it"
        return 1
    fi
    if [[ $1 == *"AWSServiceRole"* ]]; then
        echo "cannot delete legacy AWS service role $1"
        return 1
    fi
    echo "DELETING $1"
    local n="$1"
    if isInstanceProfileExists "$n"; then
        echo "deleting instance profile $n"
        local foo=$(aws --profile $PROFILE iam remove-role-from-instance-profile --instance-profile-name "$n" --role-name "$n" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to detach role from instance profile $n"
            return 1
        fi
        local foo=$(aws --profile $PROFILE iam delete-instance-profile --instance-profile-name "$n" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to delete instance profile $n"
            return 1
        fi
    fi

    local rid=$(getRoleId "$n")
    if [ -z "$rid" ]; then
        echo "no role found with name $n"
        return 1
    else
        echo "Found role with id $rid"
    fi

    local POLICIES=$(aws --profile $PROFILE iam list-attached-role-policies --role-name $n --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "failed to list attached role policies on role $n"
        return 1
    fi
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            local ATTACHMENT_COUNT=$(aws --profile $PROFILE iam get-policy --policy-arn $POLICY --query "Policy.AttachmentCount" --output text 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to get policy attachment count on role $n"
                continue
            fi
            local foo=$(aws --profile $PROFILE iam detach-role-policy --role-name $n --policy-arn $POLICY 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to detach policy $POLICY from role $n"
                continue
            fi
            if [[ $POLICY == *":aws:policy/"* ]] then
                echo "cannot delete AWS managed policy"
                continue
            fi
            if [[ 1 -eq $ATTACHMENT_COUNT ]]; then
                echo "Policy is $POLICY is only attached to $ATTACHMENT_COUNT roles, deleting it."
                aws --profile $PROFILE iam delete-policy --policy-arn $POLICY
            else
                echo "Detatch but don't delete policy because it's attached to $ATTACHMENT_COUNT roles or is AWS managed"
            fi
        done
    else
        echo "Found no attached policies"
    fi

    #Inline policies
    echo "Finding inline policies"
    local POLICIES=$(aws --profile $PROFILE iam list-role-policies --role-name $n --query "PolicyNames[]" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to list role policies on role $n"
        return 1
    fi
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            local foo=$(aws --profile $PROFILE iam delete-role-policy --role-name $n --policy-name $POLICY 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to delete role policy $POLICY for role $n"
                continue
            fi
        done
    else
    echo "Found no inline policies"
    fi
    echo "Deleting role $n"
    local foo=$(aws --profile $PROFILE iam delete-role --role-name "$n" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to delete role $n"
        return 1
    fi
    echo "ROLE $n DELETED"
    return 0
}

function createRole {
    if [ -z "$1" ]; then
        echo "you must supply role name in first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must trust policy in second parameter (see createTrustPolicy)"
        return 1
    fi
    if roleExists "$1"; then
        echo "IAM role '$1' already exists."
        return 0
    fi
    local tags=$(getTags "$STACK")
    # Create the IAM role
    local foo=$(aws --profile $PROFILE iam create-role --role-name "$1" --tags $tags --assume-role-policy-document "$2" --query "Role.RoleId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

########################################################################
### INSTANCE PROFILES           ########################################
########################################################################

function getInstanceProfileNameForInstanceName {
    if [ -z "$1" ]; then
        echo "you must instance name in first parameter"
        return 1
    fi
    local ipname="$1-instanceprofile"
    echo "$ipname"
}

function getInstanceProfileId {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam get-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    echo "$foo"
    return 0
}

function isProfileAttachedToInstance {

    if [ -z "$1" ]; then
        echo "must provide the instance profile name in the first parameter (isProfileAttached)"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "must supply instance name in second parameter"
        return 1
    fi
    local ipn=$(getInstanceProfileId "$1")
    if [ -z "$ipn" ]; then return 1; fi
    local iid=$(getInstanceId "$2")
    aws --profile $PROFILE ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$iid" --query "IamInstanceProfileAssociations[].IamInstanceProfile.Id" --output text
    if [ $? -ne 0 ]; then
        echo "failed to get instance profile associations"
        return 1
    fi
}

function associateInstanceProfile {
    if [ -z "$1" ]; then
        echo "must supply instance name in first parameter"
        return 1
    fi
    local iid=$(getInstanceId "$1")
    if [ $? -ne 0 ]; then
        echo "failed to get the instance id for instance with name $1"
        return 1
    fi

    local ipname=$(getInstanceProfileNameForInstanceName "$1")
    if ! isInstanceProfileExists "$ipname"; then
        echo "instance profile $ipname does not exist"
        return 1
    fi

    #if isProfileAttachedToInstance "$ipname" "$1"; then
    #    echo "instance $1 is already attached to instance profile $ipname"
    #    return 0
    #fi

    local foo=$(aws --profile $PROFILE ec2 associate-iam-instance-profile --iam-instance-profile Name=$ipname --instance-id $iid 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "failed to attach $ipname to instance $1"
        return 1;
    else
        echo "attached $ipname to instance $1"
    fi

    return 0
}

function isInstanceProfileExists {
    if [ -z "$1" ]; then
        echo "you must supply instance profile name in first parameter"
        return 1
    fi
    local foo=$(aws --profile ${PROFILE} iam get-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

function isRoleAttachedToInstanceProfile {
    if [ -z "$1" ]; then
        echo "you must provide instance profile name in the first parameter (isRoleAttached)"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must provide the role name in the second parameter"
        return 1
    fi
    local ips=$(getInstanceProfilesForRole "$1" "$2")
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$ips" ]; then return 1; fi
    for arn in $ips; do
        if [ "$arn"="$1" ]; then return 0; fi
    done
    return 1
}

function getInstanceProfilesForRole {
    if [ -z "$1" ]; then
        echo "you must provide instance profile name in the first parameter (getInstanceProfiles)"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must role name in the second parameter"
        return 1
    fi
    local foo=$(aws --profile $PROFILE iam list-instance-profiles-for-role --role-name $1 --query "InstanceProfiles[].InstanceProfileId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    echo "$foo"
}

function attachRoleToInstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance profile name in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "you must role name in the second parameter"
        return 1
    fi
    # is it already attached?

    if isRoleAttachedToInstanceProfile "$1" "$2"; then
        echo "role $2 already attached to instance profile $1"
        return 0
    fi

    echo "attaching role $2 to instance profile $1"

    local foo=$(aws --profile $PROFILE iam add-role-to-instance-profile --instance-profile-name "$1" --role-name "$2" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to attache role $ROLENAME to instance profile $1"
        return 1
    fi
    return 0
}

function attachManagedPoliciesToRole {
    if [ -z "$1" ]; then
        echo "you must provide the role name in the first parameter"
        return 1
    fi
        if [ -z "$2" ]; then
        echo "you must provide list of policy arns in the second parameter"
        return 1
    fi
    for p in $2; do
        attachManagedPolicyToRole "$1" "$p"
    done
}

# Creates a generic role which will be correct for most EC2 instance profiles
# The user can add policies to this role using other functions etc.
function createAndAttachEc2InstanceProfileRole {
    if [ -z "$1" ]; then
        echo "you must provide the instance profile name in the first parameter (createAndAttach)"
        return 1
    fi
    if ! isInstanceProfileExists "$1"; then
        echo "instance profile $1 does not exist. You must create it first"
        return 1
    fi
    local ROLENAME="$1-role"
    if ! roleExists "$ROLENAME"; then
        echo "Role does not exist for instance profile with name $1... creating"
        local tp=$(createTrustPolicy "ec2.amazonaws.com")
        createRole "$ROLENAME" "$tp"
        if [ $? -eq 0 ]; then
            echo "Failed to create role $ROLENAME"
            return 1
        fi
        echo "Role $ROLENAME created"
    else
        echo "Role $ROLENAME already exists"
    fi

    local arns='''
        arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy
        arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
        arn:aws:iam::aws:policy/AmazonSSMPatchAssociation
        arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess
        arn:aws:iam::aws:policy/AmazonElasticFileSystemFullAccess
    '''
    attachManagedPoliciesToRole "$ROLENAME" "$arns"
    attachRoleToInstanceProfile "$1" "$ROLENAME"
}

function destroyEc2InstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance name in first parameter"
        return 1
    fi
    local ipname="$(getInstanceProfileNameForInstanceName $1)"

    if isInstanceProfileExists "$ipname"; then
        echo "Deleting instance profile with name $1"
        local foo=$(aws --profile $PROFILE iam delete-instance-profile --instance-profile-name $ipname 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "deleted instance profile $ipname"
        else
            echo "problem deleting instance profile $ipname"
            return 1
        fi
    else
        echo "instance profile $ipname does not exist"
    fi
    local ROLENAME="$ipname-role"
    if roleExists "$ROLENAME"; then
        echo "Deleting role $ROLENAME"
        local foo=$(deleteRole "$ROLENAME")
        if [ $? -ne 0 ]; then
            echo "problem deleting role $ROLENAME"
            return 1
        fi
    else
        echo "role $ROLENAME does not exist"
    fi
}

# Creates an instance profile and adds a role to it
# You can create the role first (it must have the same name)
# or this function will create a role and leave it blank
# You can then populate the role later using the above functions
function createEc2InstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance name in first parameter"
        return
    fi

    local ipname="$(getInstanceProfileNameForInstanceName $1)"
    if [ -z "$ipname" ]; then
        echo "failed to get the name of the instance profile?"
        return 1
    fi
    echo "Instance profile name is $ipname"

    if ! isInstanceProfileExists "$ipname"; then
        local ipid=$(aws --profile $PROFILE iam create-instance-profile --instance-profile-name "$ipname" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "error creating instance profile $ipname"
            return 1
        fi
        if [ -z "$ipid" ]; then
            echo "problem creating instance profile $ipname"
            return 1
        fi
    else
        echo "Instance profile $ipname already exists"
    fi

    createAndAttachEc2InstanceProfileRole "$ipname"
    if [ $? -ne 0 ]; then
        echo "Failed to attache role to instance profile $ipname"
        return 1
    fi
    return 0
}

function deleteUnusedRolesByProfileAndDaysOld {
  if [ -z "$PROFILE" ]; then
    if [ -z "$1" ]; then
        echo "must supply profile name in first parameter"
        return 1
    else
        export PROFILE="$1"
    fi
  fi

  local total_deleted=0
  local prev_total=0
  #local ROLE_REGEX="--path-prefix /s"
  #local ROLE_REGEX="/"
  local ROLE_REGEX=""

  #days ago
  local sixhundreddays=$(date --date '600 days ago' +'%s')
  local fourhundreddays=$(date --date '400 days ago' +'%s')
  local ninetydays=$(date --date '400 days ago' +'%s')
  local ROLES=$(aws --profile $PROFILE iam list-roles $ROLE_REGEX --no-paginate --max-items 1000 --query "Roles[].RoleName" --output text)
  #aws --profile non-production iam list-roles --no-paginate --query "Roles[].RoleLastUsed" --output json
  #RoleLastUsed
  local numRoles=$(wc -w <<< "$ROLES")
  echo "Found potentially redundant $numRoles roles"
  for ROLE in $ROLES; do
    if [ "$total_deleted" -ne "$prev_total" ]; then
        echo "TOTAL DELETED $total_deleted"
        prev_total=$total_deleted
    fi
    local rl=$(aws --profile $PROFILE iam get-role --no-paginate --role-name $ROLE --output json)
    local crd=$(echo "$rl" | jq -r '.Role.CreateDate')
    if [ ! -z "$crd" ] || [[ "$crd" != "null" ]] || [[ "$crd" != "None" ]]; then
      local crdd=$(date --date $crd +'%s')
      if [ $crdd -gt $fourhundreddays ]; then continue; fi
    else
      continue
    fi
    local lud=$(echo "$rl" | jq -r '.Role.RoleLastUsed.LastUsedDate')
    if [ -z "$lud" ] || [[ "$lud" == "null" ]] || [[ "$lud" == "None" ]]; then
        echo "$ROLE [Expired - no last used info, created $crd].. Deleting."
        deleteRole "$ROLE"
        if [ $? -eq 0 ]; then
            local total_deleted=$((total_deleted+1))
        else
            echo "failed to delete role $ROLE"
        fi
        continue
    else
      #2022-08-31T15:21:34+00:00
      local d=$(date --date $lud +'%s')
      if [ $d -lt $fourhundreddays ]; then
        echo "$ROLE [Expired - $lud more than n days old. Created $crd].. Deleting."
        deleteRole "$ROLE"
        if [ $? -eq 0 ]; then
            local total_deleted=$((total_deleted+1))
        else
            echo "failed to delete role $ROLE"
        fi
        continue
      fi
    fi
  done
  echo "total deleted $total_deleted"
}

function listInstanceProfilesForPlatform {
  local rgn=$(getRegion)
  local plat=$(getPlatform)
  local foo=$(aws --profile non-production iam list-instance-profiles --query "InstanceProfiles[].InstanceProfileName" --output text)
  if [ -z "$foo" ]; then
    echo "no instance profiles found!?"
    return
  fi
  for i in $foo; do
    if [[ "$i" == *"$plat"* ]]; then
      echo "$i"
    fi
  done
}

function listIamRolesForPlatform {
  local plat=$(getPlatform)
  local rgn=$(getRegion)
  local foo=$(aws --profile non-production iam list-roles --query "Roles[].[RoleId,RoleName]" --output text)
  echo "$foo" | while read -r line
  do
    local name=$(awk '{print $NF;}' <<< "$line")
    local id=$(awk '{print $1;}' <<< "$line")
    if [[ $name == *"$plat"* ]]; then
      echo "$name"
    fi
  done
}