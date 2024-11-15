#!/bin/bash

function vpcHasEksCluster {
  local region=$(getVariable 'CURRENT_REGION' "what region are you working in?")
  local cn=$(getClusterName)
  local ips=$(aws eks list-clusters --region $region --output text | grep "$cn")
  if [ -z "$ips" ]; then
    return 1
  else
    return 0
  fi
}

#get the public ip of an EKS cluster as created by the nginx ingress controller
function getPublicIngressIp {
    local ing=$(kubectl get service/nginx-ingres-nginx-ingress-controller -n kube-system)
    if [ -z "$ing" ]; then
        return
    fi
    for i in $ing; do
      if [[ $i == *'elb.amazonaws.com' ]]; then
        local dns="$i"
      fi
    done
    if [ -z "$dns" ]; then
      return
    fi
    #do ip lookup
    local host=$(host $dns)
    for i in $host; do
      if isIpValid "$i"; then
        echo "$i"
        return
      fi
    done
}

function getClusterName {
  local plat=$(getPlatform)
  local region=$(getRegion)
  local foo=$(aws eks list-clusters --region $region --output text | grep "$plat")
  if [ -z "$foo" ]; then
    return
  fi
  local split=( $foo )
  local al=${#split[@]}
  if (( 2 != $al )); then
    return
  fi
  echo "${split[1]}"
}

function createConfigForExistingEksCluster {
  local region=$(getVariable 'CURRENT_REGION' "what region are you working in?")
  local cn=$(getClusterName)
  if [ -z "$cn" ]; then
    return
  fi
  aws eks --region "$region" update-kubeconfig --name "$cn"
}