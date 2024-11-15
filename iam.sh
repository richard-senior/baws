#!/bin/bash

function isUserAdmin {
  if [ -z "$1" ]; then
    echo "must supply username in first parameter"
    return 1
  fi
  local foo=$(aws --profile $PROFILE --region $REGION iam list-groups-for-user --user-name $1 --query "Groups[].GroupName" --output text)
  if [ -z "$1" ]; then
    return 1
  fi
  for i in $foo; do
    if [ "$i" == "admin" ]; then
      return 0
    fi
  done
  return 1
}