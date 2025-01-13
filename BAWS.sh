#!/bin/bash

############################################################
## BAWS 'Bash AWS'
############################################################
## This library is intended as a quick and dirty way of
## implementing IAC code for AWS infrastructure
## Usually people will use cloudformation or terraform but
## both of those solutions have issues with 'state management'
## which during a development stage can prove diffictult to handl.
## BAWS has a concept of looking to see if something exists
## before trying to create it or delete it which means
## re-running a script multiple times will not produce errors
## when things exist or do not exist
## See the readme for more information
##
## To use,
## * copy baws into a sub directory within your project
## * read and or edit baws/conf.sh
## * run 'source ./baws/BAWS.sh' at the top of your script
## * After which you can use any of the BAWS functions ie
## *    accountId=$(getAccountId)
## *    etc.
##
## All BAWS function will return exit code 1 if there was a problem
## TODO Method Caching : https://github.com/dimo414/bash-cache/blob/master/README.md
############################################################

# by default we disable aws response paging as this
# will prevent some commands from completing
export AWS_PAGER=""

# Get the full path of the baws library directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    export BAWS_DIR=$(realpath "${BASH_SOURCE%/*}")
else
    export BAWS_DIR=$(readlink -f "${BASH_SOURCE%/*}")
fi

source $BAWS_DIR/utils.sh

if ! isApplicationInstalled "aws"; then
    bawsLog "You must install AWS CLI before using BAWS"
fi

if ! isCanConnect; then
    bawsLog """
        BAWS cannot currently connect to AWS using profile \"$PROFILE\"
        Please edit the baws/conf.sh file or do :
        *   export PROFILE=workingprofilename
    """
fi


# Start by reading in environment variables from the conf file
source $BAWS_DIR/conf.sh
# Now source all the library files
source $BAWS_DIR/account.sh
source $BAWS_DIR/ec2.sh
source $BAWS_DIR/ami.sh
source $BAWS_DIR/efs.sh
source $BAWS_DIR/eks.sh
source $BAWS_DIR/iam.sh
source $BAWS_DIR/loadbalancer.sh
source $BAWS_DIR/rdb.sh
source $BAWS_DIR/roles.sh
source $BAWS_DIR/s3.sh
source $BAWS_DIR/securitygroups.sh
source $BAWS_DIR/ssm.sh
source $BAWS_DIR/tags.sh
source $BAWS_DIR/utils.sh
source $BAWS_DIR/vpc.sh

#function show {
#    echo "getListenerArn"
#    echo "$(getListenerArn)"
#    echo "getLbArn"
#    echo "$(getLbArn)"
#    echo "getAccountId"
#    echo "$(getAccountId)"
#    echo "getPublicSubnets"
#    echo "$(getPublicSubnets)"
#    echo "getInstanceId"
#    echo "$(getInstanceId)"
#    echo "getSecurityGroupId $sg_name"
#    echo $(getSecurityGroupId "$sg_name")
#    echo "getTargetGroupArn"
#    echo "$(getTargetGroupArn)"
#    echo "isLoadBalancerSecurityGroupExists"
#    if isLoadBalancerSecurityGroupExists; then echo "sg exists"; else echo "sg does not exist"; fi
#    echo "isLoadBalancerExists"
#    if isLoadBalancerExists; then echo "lb exists"; else echo "lb does not exist"; fi
#    echo "isTargetGroupExists"
#    if isTargetGroupExists; then echo "tg exists"; else echo "tg does not exist"; fi
#    echo "isListenerExists"
#    if isListenerExists; then echo "listener exists"; else echo "listener does not exist"; fi
#    echo "isTargetRegistered"
#    if isTargetRegistered; then echo "target is registered"; else echo "target is not registered"; fi
#}