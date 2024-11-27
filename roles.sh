#!/bin/bash

########################################################################
### POLICIES           #################################################
########################################################################

#### policies
function createTrustPolicy {
    if [ -z "$1" ]; then
        echo "you must supply the service in the first parameter (ie ec2.amazonaws.com)"
        return 1
    fi
trust=$(cat <<-END
{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"\",
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Service\": \"$1\"
            },
            \"Action\": \"sts:AssumeRole\"
        }
    ]
}
END
)
    echo "$trust"
    return 0
}

function createPolicy {
    echo "TODO THIS!"
    echo "add tags if possible"
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
    local rid=$(getRoleId "$1")
    if [ -z "$rid" ]; then
        echo "role $1 does not exist"
        return 1
    fi
    local foo=$(aws --profile $PROFILE --region $REGION iam attach-role-policy --role-name "$1" --policy-arn $2 2>/dev/null)
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
    local foo=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" --query "Role.RoleId" --output text 2>/dev/null)
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
    local foo=$(aws --profile $PROFILE --region $REGION iam list-roles --query "Roles[?RoleId==$1].RoleName" --output text 2>/dev/null)
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
    local foo=$(aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" --query "Role.Arn" --output text 2>/dev/null)
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
    if aws --profile $PROFILE --region $REGION iam get-role --role-name "$1" &>/dev/null; then
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

    local n="$1"
    if isInstanceProfileExists "$n"; then
        echo "deleting instance profile $n"
        local foo=$(aws --profile $PROFILE --region $REGION iam remove-role-from-instance-profile --instance-profile-name "$n" --role-name "$n" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to detach role from instance profile $n"
            return 1
        fi
        local foo=$(aws --profile $PROFILE --region $REGION iam delete-instance-profile --instance-profile-name "$n" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "failed to delete instance profile $n"
            return 1
        fi
        return 0
    fi

    local rid=$(getRoleId "$n")
    if [ -z "$rid" ]; then
        echo "no role found with name $n"
        return 1
    else
        echo "Found role with id $rid"
    fi

    local POLICIES=$(aws --profile $PROFILE --region $REGION iam list-attached-role-policies --role-name $n --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "failed to list attached role policies on role $n"
        return 1
    fi
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            local ATTACHMENT_COUNT=$(aws --profile $PROFILE --region $REGION iam get-policy --policy-arn $POLICY --query "Policy.AttachmentCount" --output text 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to get policy attachment count on role $n"
                return 1
            fi
            local foo=$(aws --profile $PROFILE --region $REGION iam detach-role-policy --role-name $n --policy-arn $POLICY 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to detach policy $POLICY from role $n"
                return 1
            fi
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
    local POLICIES=$(aws --profile $PROFILE iam list-role-policies --role-name $n --query "PolicyNames[]" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to list role policies on role $n"
        return 1
    fi
    if [ ! -z "$POLICIES" ]; then
        for POLICY in $POLICIES; do
            local foo=$(aws --profile $PROFILE --region $REGION iam delete-role-policy --role-name $n --policy-name $POLICY 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "failed to delete role policy $POLICY for role $n"
                return 1
            fi
        done
    else
     echo "Found no inline policies"
    fi
    echo "Deleting role $n"
    local foo=$(aws --profile $PROFILE --region $REGION iam delete-role --role-name "$n" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to delete role $n"
        return 1
    fi
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
    local tags=$(getTagsRaw "$STACK")
    # Create the IAM role
    aws --profile $PROFILE --region $REGION iam create-role \
        --role-name "$1" \
        --tags "$tags" \
        --assume-role-policy-document "$2"

    if [ $? -eq 0 ]; then return 0; fi
    return 1
}

########################################################################
### INSTANCE PROFILES           ########################################
########################################################################

function isInstanceProfileExists {
    if [ -z "$1" ]; then
        echo "you must supply instance profile name in first parameter"
        return 1
    fi
    local foo=$(aws --profile ${PROFILE} --region ${REGION} iam get-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    return 0
}

function deleteInstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
        return 1
    fi

    if ! isInstanceProfileExists "$1"; then
        echo "instance profile $1 does not exist. No need to delete it"
        return 0
    fi

    local foo=$(aws --profile $PROFILE --region $REGION iam delete-instance-profile --instance-profile-name $1 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "deleted instance profile $1"
        return 0
    else
        echo "problem deleting instance profile $1"
        return 1
    fi
}

# Creates a generic role which will be correct for almost all EC2 instance profiles
# The user can add policies to this role using other functions etc.
function createAndAttachEc2InstanceProfileRole {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
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
    fi
    echo "Attaching standard AWS managed policies to EC2 Instance role"
    attachManagedPolicyToRole "$ROLENAME" "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    if [ $? -ne 0 ]; then
        echo "Failed to add AmazonSSMManagedInstanceCore policy to role $ROLENAME"
    fi

    attachManagedPolicyToRole "$ROLENAME" "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
    if [ $? -ne 0 ]; then
        echo "Failed to add arn:aws:iam::aws:policy/AmazonSSMPatchAssociation policy to role $ROLENAME"
    fi
    attachManagedPolicyToRole "$ROLENAME" "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation"
    if [ $? -ne 0 ]; then
        echo "Failed to add arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess policy to role $ROLENAME"
    fi
    echo "attaching role to instance profile $1"
    local foo=$(aws --profile $PROFILE --region $REGION iam add-role-to-instance-profile --instance-profile-name "$1" --role-name "$1" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Failed to attache role $ROLENAME to instance profile $1"
        return 1
    fi
    return 0
}

# Creates an instance profile and adds a role to it
# You can create the role first (it must have the same name)
# or this function will create a role and leave it blank
# You can then populate the role later using the above functions
function createEc2InstanceProfile {
    if [ -z "$1" ]; then
        echo "you must instance profile name in first parameter"
        return
    fi

    if isInstanceProfileExists $1; then
        echo "instance profile $1 already exists"
        return 0
    fi

    local ipid=$(aws --profile $PROFILE --region $REGION iam create-instance-profile --instance-profile-name "$1" --query "InstanceProfile.InstanceProfileId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "error creating instance profile $1"
        return 1
    fi
    if [ -z "$ipid" ]; then
        echo "problem creating instance profile $1"
        return 1
    fi

    echo "checking for role to associate with this instance profile.."

    createAndAttachEc2InstanceProfileRole
    if [ $? -ne 0 ]; then
        echo "Failed to attache role to instance profile $1"
        return 1
    fi
    return 0
}


function deleteUnusedRolesByProfileAndDaysOld {
  if [ -z "$1" ]; then
      echo "must supply profile name in first parameter"
      return 1
  fi
  total_deleted=0
  local ROLE_REGEX="--path-prefix /s"
  #local ROLE_REGEX="/"

  #90 days ago
  local fourhundreddays=$(date --date '400 days ago' +'%s')
  local ninetydays=$(date --date '400 days ago' +'%s')
  local ROLES=$(aws --profile $1 iam list-roles $ROLE_REGEX --no-paginate --max-items 1000 --query "Roles[].RoleName" --output text)
  #aws --profile non-production iam list-roles --no-paginate --query "Roles[].RoleLastUsed" --output json
  #RoleLastUsed
  for ROLE in $ROLES; do
    echo "total deleted $total_deleted"
    local rl=$(aws --profile $1 iam get-role --no-paginate --role-name $ROLE --output json)
    local crd=$(echo "$rl" | jq -r '.Role.CreateDate')
    if [ ! -z "$crd" ] || [[ "$crd" != "null" ]] || [[ "$crd" != "None" ]]; then
      local crdd=$(date --date $crd +'%s')
      if [ $crdd -gt $ninetydays ]; then
        continue
      fi
    else
      echo "role $ROLE has no create date.. skipping"
      continue
    fi
    local lud=$(echo "$rl" | jq -r '.Role.RoleLastUsed.LastUsedDate')
    if [ -z "$lud" ] || [[ "$lud" == "null" ]] || [[ "$lud" == "None" ]]; then
      echo "$ROLE [Expired - no last used info, created $crd]"
      deleteRole $1 $ROLE
    else
      #2022-08-31T15:21:34+00:00
      local d=$(date --date $lud +'%s')
      if [ $d -lt $ninetydays ]; then
        echo "$ROLE [Expired - $lud more than n days old. Created $crd]"
        deleteRole $1 $ROLE
      else
        echo "ignoring $ROLE less than n days since last use"
      fi
    fi
  done
  echo "total deleted $total_deleted"
}

function listInstanceProfilesForPlatform {
  local rgn=$(getRegion)
  local plat=$(getPlatform)
  local foo=$(aws --profile non-production --region $rgn iam list-instance-profiles --query "InstanceProfiles[].InstanceProfileName" --output text)
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
  local foo=$(aws --profile non-production --region $rgn iam list-roles --query "Roles[].[RoleId,RoleName]" --output text)
  echo "$foo" | while read -r line
  do
    local name=$(awk '{print $NF;}' <<< "$line")
    local id=$(awk '{print $1;}' <<< "$line")
    if [[ $name == *"$plat"* ]]; then
      echo "$name"
    fi
  done
}