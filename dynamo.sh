#!/bin/bash

function cleanToolingDynamoDb {
  # for records, pipe this function to a text file like cleantoolingDynamoDb > /tmp/log.txt
  local tables="$(aws --profile tooling --region eu-west-1 dynamodb list-tables --output text)"
  local np_plats="$(getPlatforms non-production)"
  local pns=$(aws --profile tooling --region eu-west-1 dynamodb scan --table-name ee-platform-names --query "Items[].platform_name" --output text)
  for i in $pns; do
    if [[ "$np_plats" != *"$i"* ]]; then
      echo "$i - no longer exists"
      local rgn=$(aws --region='eu-west-1' --profile='tooling'  dynamodb get-item --table-name ee-platform-names --key '{"platform_name":{"S":'\"$i\"'}}'  | jq '.Item.region_name.S' |sed 's/"//g')
      echo "$i is in region $rgn"
      local envi="core"
      local tbkt=$(getS3Bucket "$rgn" "tooling")
      local npbkt=$(getS3Bucket "$rgn" "non-production")
      local kkey="vault-keys/vault-keys-$i*"
      local tkey="vault-token/vault-token-$i*"
      local bkey="consul-backup/consul-backup-$i*"
      echo "$i - deleting s3 vault token data"
      aws --profile non-production s3 rm s3://$npbkt/ --recursive --exclude "*" --include "$kkey"
      aws --profile non-production s3 rm s3://$npbkt/ --recursive --exclude "*" --include "$tkey"
      aws --profile non-production s3 rm s3://$npbkt/ --recursive --exclude "*" --include "$bkey"
      # delete lockfiles
      local key="s3://$tbkt/terraform-state/non-production/$rgn/$i"
      echo "$i deleting lockfiles from $key"
      aws --profile tooling s3 rm $key --recursive
      # delete dynamo data
      local tp="terraform-lock-$i-"
      for t in $tables; do
        if [[ "$tp" == *"$t"* ]]; then
          echo "removing table : $t"
          aws --profile=tooling  dynamodb delete-table --table-name "$t"
        fi
      done
      # delete entries in platform names
      echo "$i - deleting entry in ee-platform-names table"
      aws --profile=tooling  dynamodb delete-item --table-name ee-platform-names --key '{"platform_name":{"S":'\"$i\"'}}'
      # delete amis
    fi
  done
}

function getRegionFromDynamoDb {
  local plat=$(getPlatform)
  local region=$(aws --region='eu-west-1' --profile='tooling'  dynamodb get-item --table-name ee-platform-names --key '{"platform_name":{"S":'\"$plat\"'}}'  | jq '.Item.region_name.S' |sed 's/"//g')
  echo "$region"
}

function platformExistsInDb {
  local foo=$(getRegionFromDynamoDb)
  if [ -z "$region" ]; then
    return 1
  else
    return 0
  fi
}
function deletePlatformEntriesFromDynamoDb {
  local plat=$(getPlatform)
  aws --region='eu-west-1' --profile='tooling'  dynamodb delete-item --table-name ee-platform-names --key '{"platform_name":{"S":'\"$plat\"'}}'
}

function deleteStackEntryFromDynamoDb {
  if [ -z "$1" ]; then
    echo "must supply stack name in first parameter"
    return 1
  fi
  local plat=$(getPlatform)
  local envi=$(getEnvironment)
  local tn="terraform-lock-$plat-$envi-$1"
  #aws --region="eu-west-1" --profile="tooling"  dynamodb delete-table --table-name "terraform-lock-rmsdublin-core-vault"
  aws --region="eu-west-1" --profile="tooling"  dynamodb delete-table --table-name "$tn"
}