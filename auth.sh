#!/bin/bash
# A collection of functions for authenticating within BT

########################################
#### SSO / SSM
########################################

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
    if ! amOnVpn; then
        echo "====== INFO ======="
        echo "You're not currently on the VPN.. The chances are you should be"
        echo "==================="
    fi
    if amLoggedIn; then return 0; fi
    if ! isApplicationInstalled 'dcpcli'; then
        echo "====== INFO ======="
        echo "You need to install the dcpcli application"
        echo "==================="
        return 1
    fi
    dcpcli auth store plaintext
    dcpcli auth url set "$AUTHURL"
    dcpcli auth login -n $PROFILE
    aws configure set region eu-west-2 --profile $PROFILE
}

