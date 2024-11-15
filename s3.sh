#!/bin/bash

function getBuckets {
  local foo=$(aws --profile non-production s3api list-buckets --query "Buckets[].Name" --output text)
  for f in $foo; do
    echo "$f"
  done
}

function searchBuckets {
  if [ -z "$1" ]; then
    echo "must supply search term in first parameter"
    return 1
  fi
  local foo=$(aws --profile non-production s3api list-buckets --query "Buckets[].Name" --output text)
  for f in $foo; do
    if [[ "$f" == *"$1"* ]]; then
      echo "$f"
    fi
    local bar=$(aws --profile non-production s3api list-objects --bucket $f --query 'Contents[].{Key: Key}' --output text)
    for b in $bar; do
      if [[ "$b" == *"$1"* ]]; then
        echo "$b"
      fi
    done
  done
}

function s3KeyExists {
  if [ -z "$1" ]; then
    echo "must supply the profile name in first parameter. ie tooling or non-production"
    return 1
  fi
  if [ -z "$2" ]; then
    echo "must supply the s3 bucket in the second parameter ie ee-platform-services-master-556428197880-eu-west-1"
    return 1
  fi
  if [ -z "$3" ]; then
    echo "must supply the s3 key in the third parameter ie vault-keys/vault-keys-jx-poc-2-testjx"
    return 1
  fi

  aws s3api head-object --profile $1 --bucket $2 --key $3 > /dev/null 2>&1
  if [ $? -eq 0 ]; then
      return 0
  else
      return 1
  fi
}

function deleteS3Key {
  if [ -z "$1" ]; then
    echo "must supply the profile name in first parameter. ie tooling or non-production"
    return 1
  fi
  if [ -z "$2" ]; then
    echo "must supply the s3 bucket in the second parameter ie ee-platform-services-master-556428197880-eu-west-1"
    return 1
  fi
  if [ -z "$3" ]; then
    echo "must supply the s3 key in the third parameter ie vault-keys/vault-keys-jx-poc-2-testjx"
    return 1
  fi
  if s3KeyExists $1 $2 $3; then
    aws s3api delete-object --profile $1 --bucket $2 --key $3 > /dev/null 2>&1
      if [ $? -eq 0 ]; then
          echo "$2/$3 deleted"
      else
          echo "failed to delete $2/$3"
      fi
  else
    echo "key $2/$3 doesn't exist"
  fi
}

function getS3Bucket {
  if [ -z "$1" ]; then
    echo "must supply the region name in first parameter"
    return 1
  fi
  if [ ! -z "$2" ]; then
    local bkt=$(aws --profile $2 s3 ls | grep -oh "ee-platform-services-master-[0-9]*-$1")
  else
    local bkt=$(aws s3 ls | grep -oh "ee-platform-services-master-[0-9]*-$1")
  fi
  local ret=$bkt
  for f in $bkt; do
    if [ ! -z $f ]; then
      local ret=$f
      break
    fi
  done
  echo "$ret"
}