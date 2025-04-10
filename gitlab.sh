#!/bin/bash
#export GOCACHE=off.

function publish {
    # Check if we're running in GitLab CI environment
    if [ -z "$CI_API_V4_URL" ] || [ -z "$CI_PROJECT_ID" ]; then
        echo "Error: This function must be run within a GitLab CI pipeline"
        return 1
    fi

    # Create version tag from CI commit SHA or tag
    VERSION=${CI_COMMIT_TAG:-${CI_COMMIT_SHA:0:8}}

    echo "Publishing version: $VERSION"

    # Upload Linux binary
    if [ -f "felm" ]; then
        echo "Uploading Linux binary..."
        # Upload with specific version
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-linux-amd64"

        # Also upload as 'latest'
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-linux-amd64"
    fi

    # Similar pattern for Windows and macOS...
    if [ -f "felm.exe" ]; then
        echo "Uploading Windows binary..."
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm.exe \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-windows-amd64.exe"

        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm.exe \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-windows-amd64.exe"
    fi

    if [ -f "felmm" ]; then
        echo "Uploading macOS binary..."
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felmm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-darwin-amd64"

        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felmm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-darwin-amd64"
    fi

    echo "Successfully published binaries to GitLab Package Registry"
    echo "Version: $VERSION as 'latest'"
    return 0
}

function download {
    local GITLAB_TOKEN=$(read_properties 'GITPASSWORD')
    # Download using the retrieved version
    curl --header "Private-Token: $GITLAB_TOKEN" \
        "https://mobius-gitlab.bt.com/api/v4/projects/platformservices%2fpocs%2farcam%2ffelm/packages/generic/felm/latest/felm-darwin-amd64" \
        --output felmz
}