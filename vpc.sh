#!/bin/bash

########################################################################
### VPC           ######################################################
########################################################################

function getVpcCidrRange {
  local vpcid=$(getVpcId)
  if [ $? -ne 0 ]; then return 1; fi
  local cbr=$(aws --profile $PROFILE --region $REGION ec2 describe-vpcs --vpc-ids $vpcid --query "Vpcs[0].CidrBlock" --output text 2>/dev/null)
  if [ $? -ne 0 ]; then return 1; fi
  if [ -z "$cbr" ]; then return 1; fi
  echo "$cbr"
  return 0
}

function getVpcId {
    if [ ! -z "$VPCID" ]; then
        echo "$VPCID"
        return 0
    fi
    if [ ! -z "$PLATFORM" ]; then
        local vpcid=$(aws ec2 --profile $PROFILE --region $REGION describe-vpcs --filters "Name=tag:platform-name, Values=$PLATFORM" --query "Vpcs[*].[VpcId]" --output text 2>/dev/null)
        if [ ! -z "$vpcid" ]; then
            export VPCID=$vpcid
            echo "$VPCID"
            return 0
        else
            return 1
        fi
    fi
    return 1
}

function getPrivateSubnetId {
    local scheme="private"
    if [ -z "$1" ]; then
        echo "must supply index (which subnet) in first parmeter"
        echo "Generally you'll have many subnets on a vpc"
        return
    fi
    local vpcid=$(getVpcId)
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    ret=()
    for i in $sn; do
        ret+=("$i")
    done
    echo "${ret[$1]}"
}

function getCommaDelimitedSubnetsForPlatform {
    local scheme="private"
    local vpcid=$(getVpcId)
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    local ret=""
    for i in $sn; do
        ret="$ret$i,"
    done
    ret="${ret%?}"
    echo "$ret"
}

function getSpaceDelimitedSubnetsForPlatform {
    local scheme="private"
    if [ ! -z "$1" ]; then local scheme="$1"; fi
    local vpcid=$(getVpcId)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$vpcid" ]; then return 1; fi
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$sn" ]; then return 1; fi
    local ret=""
    for i in $sn; do
        ret="$ret$i "
    done
    echo "$ret"
    return 0
}

function getSubnet {
  # gets the first subnet for the vpc for the scheme in $1
    local scheme="private"
    if [ ! -z "$1" ]; then local scheme="$1"; fi
    local vpcid=$(getVpcId)
    # aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0099b918d2a911701 --region us-east-2 --query "Subnets[].SubnetId" --output text
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[0].SubnetId" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    echo "$sn"
}

function getSubnetsForPlatform {
    local scheme="private"
    if [ ! -z "$1" ]; then local scheme="$1"; fi
    local vpcid=$(getVpcId)
    # aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0099b918d2a911701 --region us-east-2 --query "Subnets[].SubnetId" --output text
    local sn=$(aws --profile $PROFILE --region $REGION ec2 describe-subnets --filters Name=vpc-id,Values=$vpcid "Name=tag:scheme,Values=$scheme" --query "Subnets[].SubnetId" --output text)
    local ret="["
    for i in $sn; do
        ret+="\"$i\","
    done
    ret="${ret%?}"
    ret+="]"
    echo "$ret"
}

function deleteSubnetGroup {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    if ! isDbSubnetGroupExists $1; then
        echo "DB Subnet Group '$1' does not exist. Nothing to delete."
        return
    fi
    aws --profile $PROFILE --region $REGION rds delete-db-subnet-group --db-subnet-group-name "$1"
    if [ $? -eq 0 ]; then
        echo "DB Subnet Group '$1' has been successfully deleted."
        return 0
    else
        echo "Failed to delete DB Subnet Group '$1'. It might not exist or there might be associated resources."
        return 1
    fi
}

function isDbSubnetGroupExists {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    aws --profile $PROFILE --region $REGION rds describe-db-subnet-groups --db-subnet-group-name "$1" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}
function createDbSubnetGroup {
    if [ -z "$1" ]; then
        echo "you must subnet group name in first parameter"
        return
    fi

    if isDbSubnetGroupExists $1; then
        echo "DB Subnet Group '$1' already exists. Nothing to do."
        return
    fi

    SUBNETS="$(getSubnetsForPlatform)"

    if [ -z "$SUBNETS" ]; then
        echo "No subnets found for platform '$PLATFORM'. Cannot create DB Subnet Group."
        return
    fi

    echo "Creating subnet group with subnets : $SUBNETS"
    aws --profile $PROFILE --region $REGION rds create-db-subnet-group \
        --db-subnet-group-name $1 \
        --db-subnet-group-description "Subnet group for the aurora DB that backs devlake" \
        --subnet-ids $SUBNETS \
        --tags $(getTagsRaw "$1")
}


function listVpcPeeringConnectionsForPlatform {
  local rgn=$(getRegion)
  local vpc=$(getVpcId)
  local pcs=$(aws --profile non-production --region $rgn ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$vpc" --query "VpcPeeringConnections[].VpcPeeringConnectionId" --output text)
  echo "$pcs"
}

function deleteVpcPeeringConnectionsForPlatform {
  local foo=$(listVpcPeeringConnectionsForPlatform)
  local rgn=$(getRegion)
  for i in $foo; do
    aws --profile non-production --region $rgn ec2 delete-vpc-peering-connection --vpc-peering-connection-id $i
    echo "$i"
  done
}


function getNatGatewaysForPlatform {
  if [ -z $1]; then
    local plat=$(getPlatform)
  else
    local plat=$1
  fi
  local ngwids=$(aws --profile non-production ec2 describe-nat-gateways --filter "Name=tag:platform-name,Values=$plat" --query "NatGateways[].NatGatewayId" --output text)
  echo "$ngwids"
}

function getNatGatewaysForVpcId {
  local rgn=$(getRegion)
  local vpc=$(getVpcId)
  local ids=$(aws --profile non-production --region $rgn ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --query "NatGateways[].NatGatewayId" --output text)
  echo "$ids"
}

function deleteNatGatewaysForPlatform {
  local foo=$(getNatGatewaysForVpcId)
  local rgn=$(getRegion)
  for i in $foo;do
    aws --profile non-production --region $rgn ec2 delete-nat-gateway --nat-gateway-id $i
  done
}


###################
# Network Interfaces
###################

function deleteNetworkInterfaces {
  local foo=$(getNetworkInterfacesForPlatform)
  if [[ -z "$foo" ]]; then
    echo "no network intefaces for this platform"
    return
  fi
  local a=( $foo )
  for i in ${a[*]}; do
    aws --profile $PROFILE --region $REGION ec2 delete-network-interface --network-interface-id $i
  done
}

function getNetworkInterfacesForPlatform {
  local vpcid=$(getVpcId)
  if [ -z "$vpcid" ]; then
    return
  fi
  #aws ec2 --profile non-production --region eu-west-1 describe-network-interfaces --filters "Name=vpc-id,Values=vpc-0219a66f6361bc1ad" --query "NetworkInterfaces[].[NetworkInterfaceId]" --output text
  local foo=$(aws ec2 --profile $PROFILE --region $REGION describe-network-interfaces --filters "Name=vpc-id,Values=$VPCID" --query "NetworkInterfaces[].[NetworkInterfaceId]" --output text)
  echo "$foo"
}

function listVpcEndpoints {
  local rgn=$(getRegion)
  local vpcid=$(getVpcId)
  local foo=$(aws --profile non-production --region $rgn ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpcid" --query "VpcEndpoints[].VpcEndpointId" --output text)
  echo "$foo"
}

function deleteVpcEndpoints {
  local rgn=$(getRegion)
  local vpcid=$(getVpcId)
  if [ -z "$vpcid" ]; then
    return
  fi
  local foo=$(listVpcEndpoints)
  if [[ -z "$foo" ]]; then
    echo "no vpc endpoints for this platform"
    return
  fi
  for i in $foo; do
    aws --profile non-production --region $rgn ec2 delete-vpc-endpoints --vpc-endpoint-ids $i
  done
}

function deleteVpc {
  local rgn=$(getRegion)
  local vpc=$(getVpcId)
  if [ -z "$vpc" ]; then
    return
  fi
  aws --profile non-production --region $rgn ec2 delete-vpc --vpc-id $vpc
}