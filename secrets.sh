#!/bin/bash

########################################################################
### Handles local secrets files in various formats and
### AWS secretsmanager functions
########################################################################

function getSecrets {
    # first try reading the configured local secrets file
    if [ -z "$BAWS_SECRETS_FILE" ] || [ ! -f "$BAWS_SECRETS_FILE" ]; then
        echo "The environment variable BAWS_SECRETS_FILE is not set or the file does not exist"
        echo "attempting to recreate local secrets file from aws"
        local foo=$(updateJsonFromAws)
    fi

    local foo=$(getSecretsFromLocalFile)
    if [ $? -eq 0 ] && [ -f "$BAWS_SECRETS_FILE" ]; then
        return 0
    fi

    # if that failed, try reading the secrets from aws
    local foo=$(getSecretsFromAWS)
    if [ $? -eq 0 ]; then
        bawsLog "Failed to get secrets from both the local file and aws secretsmanager"
        return 1
    fi
    exportSecretsFromJson "$foo"
}

function addOrUpdateSecretToFile {
    # Adds the secret key value pair given in $1 and $2 to the local secrets file
    if [ -z "$BAWS_SECRETS_FILE" ]; then
        bawsLog """
            The environment variable BAWS_SECRETS_FILE is not set.
            This is required to get secrets from a local file.
            If you wish to use secrets with BAWS then please create
            a file which is not checked in (is in gitignore etc.) and
            set export the variable with its path ie. :
            BAWS_SECRETS_FILE=~/.secrets etc.

            The file should be of the format:
            {"secretone", "somesecrete",
             "secretwto": "anothersecret"}
            etc.
        """
        return 1
    fi
    if [ -z "$1" ]; then
        echo "You must supply the secret keyname (ie my-secret) in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "You must supply the secret value (ie verysecretvalue) in the second parameter"
        return 1
    fi
    # Create file with empty JSON object if it doesn't exist
    if [ ! -f "$BAWS_SECRETS_FILE" ]; then
        echo "Creating local secrets file $BAWS_SECRETS_FILE. Please ensure it is in your .gitignore file"
        echo '{}' > "$BAWS_SECRETS_FILE"
    fi
    # here replace the below with a call to the exportSecretsFromJson function
    # before saving the file back to local
    local fileContent="$(cat "$BAWS_SECRETS_FILE")"
    local newSecrets=$(addSecretToJson "$fileContent" "$1" "$2")
    if [ $? -ne 0 ] || [ -z "$newSecrets" ]; then
        bawsLog "Failed to update json with new values"
        return 1
    fi
    echo "$newSecrets" > $BAWS_SECRETS_FILE
    export BAWS_SECRETS_LAST_LOCAL_LOAD="$(date +%s)"
}

function exportSecretsFromJson {
    # parses the given json string into
    # a space or newline delimited list for use
    # in bash for loop
    if [ -z "$1" ]; then
        echo "You must supply a json string in the first parameter"
        return 1
    fi
    local secrets=$(getSecretsFromJson "$1")
    for secret in $secrets; do
        export $secret
    done
}

function getSecretsFromJson {
    # Given a json string of the form :
    # {"secretone", "somesecrete",
    # "secretwto": "anothersecret"}
    # parses and exports each key pair value
    if [ -z "$1" ]; then
        echo "You must supply a json string in the first parameter"
        return 1
    fi
    # parse in the json key pair value file and export each secret
    local secrets=$(echo "$1" | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]')
    if [ $? -ne 0 ]; then
        echo "Failed to parse secrets json"
        return 1
    fi
    if [ -z "$secrets" ]; then
        echo "No secrets found in json"
        return 1
    fi
    for secret in $secrets; do
        echo "$secret"
    done
}

function addSecretToJson {
    # given a json string, parse the
    # string and use JQ to add a new value to the json
    # before finally echoing out the new json complete with
    # the new key value pair
    if [ -z "$1" ]; then
        echo "You must supply a json string in the first parameter"
        return 1
    fi
    if [ -z "$2" ]; then
        echo "You must pass the new secret key in the second parameter (ie SECRRAT_KEY)"
        return 1
    fi
    if [ -z "$3" ]; then
        echo "You must pass the new secret value in the second parameter (ie supersecretvalue)"
        return 1
    fi
    local json="$1"
    local isValid=$(echo "$json" | jq -r '.' 2>/dev/null)
    if [ $? -ne 0 ]; then
        bawsError "The given json is not valid"
        return 1
    fi
    local key="$2"
    local value="$3"
    # add or update the key value pair
    local newJson=$(echo "$json" | jq --arg k "$key" --arg v "$value" '(.[$k] = $v)' 2>/dev/null)
    if [ $? -ne 0 ]; then
        bawsError "Failed to update existing key value pair in the given json"
        return 1
    fi
    echo "$newJson"
}

function getSecretsFromLocalFile {
    # if the location of the file is given in BAWS_SECRETS_FILE
    # then read in the secrets and export them
    # otherwise check $1. If $1 doesn't exist return error
    # Parses in a JSON key pair value file and exports each
    # secret

    #if [ -n "$BAWS_SECRETS_LAST_LOCAL_LOAD" ]; then
    #    echo "secrets already loaded"
    #    return 0
    #fi
    if [ -z "$BAWS_SECRETS_FILE" ]; then
        bawsLog """
            The environment variable BAWS_SECRETS_FILE is not set.
            This is required to get secrets from a local file.
            If you wish to use secrets with BAWS then please create
            a file which is not checked in (is in gitignore etc.) and
            set export the variable with its path ie. :
            BAWS_SECRETS_FILE=~/.secrets etc.

            The file should be of the format:
            {"secretone", "somesecrete",
             "secretwto": "anothersecret"}
            etc.
        """
        return 1
    fi
    if [ -d "$BAWS_SECRETS_FILE" ]; then
        bawsLog """
            The environment variable BAWS_SECRETS_FILE is set ($BAWS_SECRETS_FILE)
            but it does not point to a valid file.
            Please check the path is correct and the file exists.
        """
        return 1
    fi
    export BAWS_SECRETS_LAST_LOCAL_LOAD="$(date +%s)"
    echo $(cat "$BAWS_SECRETS_FILE")
}

function getSecretsFromEc2 {
    # called by scripts running within an instance profile
    if [ -z "$BAWS_SECRETS_PREFIX" ]; then
        echo "you must set the environment variable BAWS_SECRETS_PREFIX"
        return 1
    fi
    local secretsName="$BAWS_SECRETS_PREFIX"
    # get the secrets from AWS
    local secretExists=$(aws secretsmanager describe-secret --secret-id "$secretsName" --query "Name" --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$secretExists" ]; then
        echo "Secret $secretsName does not exist in aws"
        return 1
    fi
    # get the secrets which will be a json string
    local secretsValue=$(aws secretsmanager get-secret-value --secret-id "$secretsName" --query "SecretString" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$secretsValue" ]; then return 1; fi
    #echo "$secretsValue" > ./.secrets.json
    exportSecretsFromJson "$secretsValue"
}

function getSecretsFromAWS {
    # get secrets from AWS secretsmanager
    # secrets for this project will be prefixed with
    # the string given in the env variable named AWS_SECRETS_PREFIX
    # So this function finds all secrets with that prefix
    # If any secrets are found then remove the prefix and use the
    # addOrUpdateSecretToFile to put them in the local secrets file
    # this will also re-export the secrets file into env variables
    if [ -z "$BAWS_SECRETS_PREFIX" ]; then
        echo "you must set the environment variable AWS_SECRETS_PREFIX"
        return 1
    fi
    local secretsName="$BAWS_SECRETS_PREFIX"
    # get the secrets from AWS
    local secretExists=$(aws --profile $PROFILE --region $REGION secretsmanager describe-secret --secret-id "$secretsName" --query "Name" --output text 2>/dev/null)
    if [ $? -ne 0 ] && [ -z "$secretExists" ]; then
        bawsError "Secret $secretsName does not exist in aws"
        return 1
    fi

    # get the secrets which will be a json string
    local secretsValue=$(aws --profile $PROFILE --region $REGION secretsmanager get-secret-value --secret-id "$secretsName" --query "SecretString" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$secretsValue" ]; then return 1; fi
    echo "$secretsvalue"
}

function updateJsonFromAws {
    if [ -z "$BAWS_SECRETS_FILE" ]; then
        echo "you must set the environment variable BAWS_SECRETS_FILE which specifies the location of the"
        echo "local secrets file. This should be a hidden file that is not checked in (ie .gitignore etc)"
        return 1
    fi
    if [ -z "$BAWS_SECRETS_PREFIX" ]; then
        bawsLog '''
            you must set the environment variable BAWS_SECRETS_PREFIX which should indicate
            the name of a key in aws secrets manager in this account which contains the
            secrets for this stack
        '''
        return 1
    fi
    local secretsValue=$(aws --profile $PROFILE --region $REGION secretsmanager get-secret-value --secret-id "$BAWS_SECRETS_PREFIX" --query "SecretString" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$secretsValue" ]; then return 1; fi
    echo "$secretsValue" > "$BAWS_SECRETS_FILE"
    bawsLog '''
        Recreated local secrets file $BAWS_SECRETS_FILE from aws secrets manager
        you can now exit the secrets in this local file
        you can re-sync the local secrets with the remote ones by running
        updateAwsFromLocalSecrets
    '''
}

function updateAwsFromJson {
    # update AWS secretsmanager from the local secrets file
    # if the secret does not exist in AWS then it should be added
    # if the secret does not exist in the local secrets file then it should be added
    if [ -z "$BAWS_SECRETS_PREFIX" ]; then
        echo "you must set the environment variable AWS_SECRETS_PREFIX"
        return 1
    fi
    if [ -z "$1" ]; then
        echo "You must supply a json string in the first parameter"
        return 1
    fi
    local secretName="$BAWS_SECRETS_PREFIX"
    # get the secrets from the local secrets file
    local secrets="$1"
    if [ -z "$secrets" ]; then return 1; fi
    # now use the BAWS_SECRETS_PREFIX as the key
    # and add or update the AWS secrets with the value of $secrets
    # check if the secret already exists in AWS
    local secretExists=$(aws --profile $PROFILE --region $REGION secretsmanager describe-secret --secret-id "$secretName" --query "Name" --output text 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$secretExists" ]; then
        # replace this secret with the new value
        local foo=$(aws --profile $PROFILE --region $REGION secretsmanager put-secret-value --secret-id "$secretName" --secret-string "$secrets" 2>/dev/null)
        echo "$foo"
        if [ $? -ne 0 ]; then return 1; fi
    else
        # if it doesn't then add it
        local foo=$(aws --profile $PROFILE --region $REGION secretsmanager create-secret --name "$secretName" --secret-string "$secrets" 2>/dev/null)
        if [ $? -ne 0 ]; then return 1; fi
    fi
}

function updateAwsFromLocalSecrets {
    local secrets=$(cat "$BAWS_SECRETS_FILE")
    updateAwsFromJson "$secrets"
}