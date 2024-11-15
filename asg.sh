#!/bin/bash


function getAutoscalingGroupsForPlatform {
  local plat=$(getPlatform)
  local region=$(getRegion)
  #first we have to get the group names form any running instances
  getInstancesForPlatform
  if [ -z $RESOURCE_INSTANCES ]; then
    echo "no instances found"
    return
  fi
  local ret=()
  for i in ${RESOURCE_INSTANCES[@]}; do
    local asg=$(aws autoscaling describe-auto-scaling-instances --region $region --instance-ids $i --query "AutoScalingInstances[].AutoScalingGroupName" --output text)
    if [ ! -z $asg ]; then
      #todo fix problem of not being able to append the 'ret' array here!
      echo "$asg"
    fi
  done
}

function deleteAutoscalingGroupsForPlatform {
  local region=$(getRegion)
  #first we have to get the group names form any running instances
  getInstancesForPlatform 'running'
  if [ -z $RESOURCE_INSTANCES ]; then
    echo "no instances found, so no autoscaling groups to delete"
    return
  else
    echo "found instances for platform.."
  fi
  for i in ${RESOURCE_INSTANCES[@]}; do
    local asg=$(aws autoscaling describe-auto-scaling-instances --region $region --instance-ids $i --query "AutoScalingInstances[].AutoScalingGroupName" --output text)
    if [ ! -z $asg ]; then
      echo "found autoscaling group $asg"
      aws autoscaling delete-auto-scaling-group --region $region --auto-scaling-group-name $asg --force-delete
    else
      echo "instance $i has no associated autoscaling group to delete"
    fi
  done
}