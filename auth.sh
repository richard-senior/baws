#!/bin/bash
# A collection of functions for authenticating within BT

########################################
#### SSO / SSM
########################################

function console() {
    # Opens the aws console in a new browser window
    if [ -z "$PROFILE" ]; then
        if [ -z "$1" ]; then
            echo "You must supply the PROFILE in the first parameter or configure the PROFILE env variable"
            return 1
        else
            PROFILE="$1"
        fi
    fi
    if [ -z "$REGION" ]; then
        if [ -z "$2" ]; then
            echo "You must supply the REGION in the second parameter or configure the REGION env variable"
            return 1
        else
            REGION="$2"
        fi
    fi
    local st=$(aws --profile npt configure get aws_session_token --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$st" ]; then
        echo "You are not logged in. Please login first using DCP CLI (type 'lin' etc at the prompt)."
        return 1
    fi
    local ak=$(aws --profile npt configure get aws_access_key_id --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$ak" ]; then
        echo "You are not logged in. Please login first using DCP CLI (type 'lin' etc at the prompt)."
        return 1
    fi
    local sk=$(aws --profile npt configure get aws_secret_access_key --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$sk" ]; then
        echo "You are not logged in. Please login first using DCP CLI (type 'lin' etc at the prompt)."
        return 1
    fi
    local SESSION_JSON="{\"sessionId\": \"$ak\",\"sessionKey\": \"$sk\",\"sessionToken\": \"$st\"}"
    local SESSION_JSON_ENCODED=$(echo $SESSION_JSON | jq -sRr @uri)
    # Create a sign-in token
    local SIGNIN_TOKEN=$(curl -s "https://signin.aws.amazon.com/federation?Action=getSigninToken&SessionDuration=3600&Session=$SESSION_JSON_ENCODED")
    # Extract the sign-in token
    local SIGNIN_TOKEN=$(echo $SIGNIN_TOKEN | jq -r '.SigninToken')
    # Construct the URL
    local CONSOLE_URL="https://signin.aws.amazon.com/federation?Action=login&Issuer=Example.org&Destination=https%3A%2F%2Fconsole.aws.amazon.com%2F&SigninToken=$SIGNIN_TOKEN"
    open -n -a "Google Chrome" --args '--new-window' "$CONSOLE_URL"
}

function amLoggedIn {
    if [ -z "$ACCOUNTID" ]; then
        if [ -z "$1" ]; then
            echo "You must supply the accountid in the first parameter or configure the ACCOUNTID env variable in conf.sh"
            return 1
        else
            ACCOUNTID="$1"
        fi
    fi

    local foo=$(aws --profile $PROFILE --region $REGION sts get-caller-identity --query "Account" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    if [ "$foo" != "$ACCOUNTID" ]; then return 1; fi
    return 0
}

function amOnVpn {
    local foo=$(ifconfig -a | grep -c 'utun4')
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$foo" ]; then return 1; fi
    if [ "$foo" != "1" ]; then return 1; fi
    return 0
}

function login {
    if amLoggedIn; then
        echo "you're already logged in with profile $PROFILE"
        echo "opening a new browser window"
        console
        return 0
    fi
    if ! isApplicationInstalled 'dcpcli'; then
        echo "====== INFO ======="
        echo "You need to install the dcpcli application"
        echo "==================="
        return 1
    fi
    dcpcli auth url set "$AUTHURL"
    if [ -n "$SET_LOGIN_TIMETOUT" ]; then
        echo "setting timeout"
        dcpcli auth login -n $PROFILE --session-timeout 480
    else
        dcpcli auth login -n $PROFILE
    fi
    aws configure set region $REGION --profile $PROFILE
    console
}