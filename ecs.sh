#!/bin/bash

function createEcsDockerContext {
    # you must create docker context and export it to a local file
    # to do this, first make sure you have an aws profile configured for the account
    # on which you wish to deploy this application (ECS on an AWS account)
    # now run : docker context create ecs nonprod-ecs
    # then run : docker context export nonprod-ecs
    docker context use default
    docker context rm nonprod-ecs
    docker context create ecs nonprod-ecs --profile $PROFILE
}