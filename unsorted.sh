#!/bin/bash
#export GOCACHE=off.

function installApp() {
    if [ -z "$1" ]; then
        echo "must pass app name in first param" >&2
        return 1
    fi
    if isApplicationInstalled "$1"; then
        echo "$1 is already installed"
        return 0
    fi
    # Detect OS type
    local o="$OSTYPE"
    if [ -z "$o" ]; then
        local o="$(uname -s)"
    fi
    echo "OS is : $o"
    if [[ "$o" == "darwin"* ]]; then
        # macOS
        if command -v brew &>/dev/null; then
            echo "Using Homebrew to install app..."
            brew install "$1"
        fi
    elif [[ "$o" =~ [Ll][Ii][Nn][Uu][Xx] ]]; then
        # Linux
        if command -v apt-get &>/dev/null; then
            echo "Using apt to install app..."
            sudo apt-get update && sudo apt-get install -y "$1"
        elif command -v dnf &>/dev/null; then
            echo "Using dnf to install app..."
            sudo dnf install -y "$1"
        elif command -v yum &>/dev/null; then
            echo "Using yum to install app..."
            sudo yum install -y "$1"
        elif command -v pacman &>/dev/null; then
            echo "Using pacman to install app..."
            sudo pacman -Sy "$1" --noconfirm
        elif command -v zypper &>/dev/null; then
            echo "Using zypper to install app..."
            sudo zypper install -y "$1"
        elif command -v apk &>/dev/null; then
            echo "Using apk to install app..."
            apk add --no-cache "$1"
        else
            echo "No supported package manager found. Please install app manually."
            return 1
        fi
    else
        echo "Unsupported operating system: $o"
        return 1
    fi
    # Verify installation
    if isApplicationInstalled "$1"; then
        return 0
    else
        echo "Failed to install $1"
        return 1
    fi
}

function cleanPipelines() {
    echo "attempting to clean up pipeline history logs in Gitlab"
    # ensure JQ is installed
    installApp "curl"
    installApp "jq"

    if [ -z "$CI_JOB_TOKEN" ]; then
        local ACCESSTOKEN="$(read_properties 'GITPASSWORD')"
        if [ -z "$ACCESSTOKEN" ]; then
            echo "Error: No access token provided" >&2
            return 1
        fi
        local HEADER="PRIVATE-TOKEN:"
    else
        local ACCESSTOKEN="$CI_JOB_TOKEN"
        local HEADER="JOB-TOKEN:"
    fi
    if [ -z "$CI_API_V4_URL" ]; then
        local GITLABURL="https://mobius-gitlab.bt.com/api/v4"
    else
        local GITLABURL="$CI_API_V4_URL"
    fi
    if [ -z "$CI_PROJECT_ID" ]; then
        local PROJID="platformservices%2Fpocs%2Farcam%2Ffelm"
    else
        local PROJID="$CI_PROJECT_ID"
    fi
    if [ -z "$ACCESSTOKEN" ]; then
        echo "Error: No access token provided" >&2
        return 1
    fi

    local pipeline_ids=$(curl -sS --header "$HEADER $ACCESSTOKEN" "$GITLABURL/projects/$PROJID/pipelines?per_page=100" 2> /dev/null | jq -r '.[].id')

    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve pipelines"
        curl -sS --header "$HEADER $ACCESSTOKEN" "$GITLABURL/projects/$PROJID/pipelines?per_page=100"
        echo ""
        echo ""
        return 0
    fi

    if [ -z "$pipeline_ids" ]; then
        echo "No pipeline history found.."
        return 0
    fi

    # Process each pipeline ID line by line
    echo "$pipeline_ids" | while read -r pipelineid; do
        curl -sS --header "$HEADER $ACCESSTOKEN" --request "DELETE" "$GITLABURL/projects/$PROJID/pipelines/$pipelineid"
        if [ $? -ne 0 ]; then
            echo "Removing pipeline job history: $pipelineid"
            curl -sS --header "$HEADER $ACCESSTOKEN" "$GITLABURL/projects/$PROJID/pipelines?per_page=100"
            echo "Error: Failed to retrieve pipelines" >&2
            echo ""
            echo ""
            return 0
        fi
    done
    echo ""
    echo ""
}

function cleanArtifacts {
    echo "attempting to clean up old binary releases in Gitlab Repository.."
    if [ -z "$CI_JOB_TOKEN" ]; then
        local ACCESSTOKEN="$(read_properties 'GITPASSWORD')"
        if [ -z "$ACCESSTOKEN" ]; then
            echo "Error: No access token provided" >&2
            return 1
        fi
        local HEADER="PRIVATE-TOKEN:"
    else
        local ACCESSTOKEN="$CI_JOB_TOKEN"
        local HEADER="JOB-TOKEN:"
    fi
    if [ -z "$CI_API_V4_URL" ]; then
        local GITLABURL="https://mobius-gitlab.bt.com/api/v4"
    else
        local GITLABURL="$CI_API_V4_URL"
    fi
    if [ -z "$CI_PROJECT_ID" ]; then
        local PROJID="platformservices%2Fpocs%2Farcam%2Ffelm"
    else
        local PROJID="$CI_PROJECT_ID"
    fi
    if [ -z "$ACCESSTOKEN" ]; then
        echo "Error: No access token provided" >&2
        return 1
    else
        echo "got a gitlab token.. Cleaning Pipeline Job history"
    fi

    local PACKAGE_FILES=$(curl -sS --header "$HEADER $ACCESSTOKEN" \
       "${GITLABURL}/projects/${PROJID}/packages" \
       | jq -r '.[].id')

    if [ $? -ne 0 ]; then
        echo "Error: Failed to retrieve packages" >&2
        return 0
    fi
    if [ -z "$PACKAGE_FILES" ]; then
        echo "there are no old artifacts" >&2
        return 0
    fi

    if [ -n "$PACKAGE_FILES" ]; then
        echo "$PACKAGE_FILES" | while read -r id; do
            echo "removing package $id"
            curl -sS --request DELETE \
                --header "$HEADER $ACCESSTOKEN" \
                "${GITLABURL}/projects/${PROJID}/packages/${id}"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to delete package $id" >&2
            fi
        done
    fi

    # Wait a moment for deletion to complete
    sleep 5
}

function isApplicationInstalled() {
    if [ -z "$1" ]; then
      echo "must supply the name of the command in the first parameter"
      return 1
    fi
    if [ -z "$(command -v $1)" ]; then
        return 1
    else
        return 0
    fi
}

function read_properties {
    local search_key="$1"
    local file="${HOME}/.aws/passwords.txt"

    if [ -z "$search_key" ]; then
        echo "Error: No key provided" >&2
        return 1
    fi

    if [ ! -f "$file" ]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi

    # Use -r to prevent backslash escaping
    # Use -d '' to read the entire line including the ending
    while IFS='=' read -r -d $'\n' key value || [ -n "$key" ]; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ || -z $key ]] && continue

        # Remove any leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [ "$key" = "$search_key" ]; then
            echo "$value"
            return 0
        fi
    done < "$file"

    return 1
}

function buildMac {
    echo "--macos"
    export GOOS=darwin
    go env -w GOOS=darwin
    export GOARCH=amd64
    go env -w GOARCH=amd64

    go build -o felmm -ldflags="-s -w" -trimpath ./cmd/main.go
    if [ $? -ne 0 ]; then
        return 1
    fi
    chmod +x ./felmm
    return 0
}

function buildWindows {
    echo "--windows"
    export GOOS=windows
    go env -w GOOS=windows
    export GOARCH=amd64
    go env -w GOARCH=amd64
    go build -o felm.exe -ldflags="-s -w" -trimpath ./cmd/main.go
    if [ $? -ne 0 ]; then
        return 1
    fi
    return 0
}

function buildAlpine {
    # musl libc
    echo "--linux (alpine)"
    export GOOS=linux
    go env -w GOOS=linux
    export GOARCH=amd64
    go env -w GOARCH=amd64
    go build -o felma -ldflags="-s -w" -trimpath ./cmd/main.go
    if [ $? -ne 0 ]; then
        return 1
    fi
    chmod +x ./felma
    return 0
}

function buildLinux {
    echo "--linux (general)"
    export CGO_ENABLED=0
    export GOOS=linux
    go env -w CGO_ENABLED=0
    go env -w GOOS=linux
    export GOARCH=amd64
    go env -w GOARCH=amd64
    go build -a -ldflags '-extldflags "-static"' -o felm -trimpath ./cmd/main.go
    if [ $? -ne 0 ]; then
        return 1
    fi
    chmod +x ./felm
    return 0
}

function kubectlContextExists {
    local context_name="$1"
    if kubectl config get-contexts | grep -q "$context_name"; then
        return 0
    else
        return 1
    fi
}

function switchToLocalKubectlContext {
    if ! isApplicationInstalled "kubectl"; then
        echo "kubectl is not installed"
        return 1
    fi
    local cc="$(kubectl config current-context)"
    kubectl config use-context docker-desktop
    kubectl create namespace argocd
    kubectl apply -k https://github.com/argoproj/argo-cd/manifests/crds\?ref\=stable
}

function run {
    # Detect the operating system
    local os_type=$(uname -s)

    case "$os_type" in
        "Darwin")  # macOS
            if [ -f "./felmm" ]; then
                ./felmm "$@"
            else
                echo "Error: macOS executable (felmm) not found"
                return 1
            fi
            ;;
        "Linux")   # Linux
            if [ -f "./felm" ]; then
                ./felm "$@"
            else
                echo "Error: Linux executable (felm) not found"
                return 1
            fi
            ;;
        *)
            echo "Error: Unsupported operating system: $os_type"
            return 1
            ;;
    esac
}

function publish {
    # Check if we're running in GitLab CI environment
    if [ -z "$CI_API_V4_URL" ] || [ -z "$CI_PROJECT_ID" ]; then
        echo "Error: This function must be run within a GitLab CI pipeline"
        return 1
    fi

    if [ ! -f "felm" ] && [ ! -f "felmm" ] && [ ! -f "felm.exe" ]; then
        echo "Error: No binary files found (felm, felmm, felm.exe)"
        echo "Please ensure the build process completed successfully"
        return 1
    fi

    # start by cleaning the current pipline
    cleanPipelines
    # remove old built binaries
    cleanArtifacts

    # Create version tag from CI commit SHA or tag
    VERSION=${CI_COMMIT_TAG:-${CI_COMMIT_SHA:0:8}}

    echo "Publishing version: $VERSION"

    # Upload Linux binary
    if [ -f "felm" ]; then
        echo "Uploading Linux binary..."
        # Upload with specific version
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: ${VERSION}" \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-linux-amd64"

        # Also upload as 'latest' with overwrite
        curl --request PUT \
             --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: latest" \
             --upload-file felm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-linux-amd64"
    fi

    # Windows binary
    if [ -f "felm.exe" ]; then
        echo "Uploading Windows binary..."
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felm.exe \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: ${VERSION}" \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-windows-amd64.exe"

        curl --request PUT \
             --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: latest" \
             --upload-file felm.exe \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-windows-amd64.exe"
    fi

    # macOS binary
    if [ -f "felmm" ]; then
        echo "Uploading macOS binary..."
        curl --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --upload-file felmm \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: ${VERSION}" \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/${VERSION}/felm-darwin-amd64"

        curl --request PUT \
             --header "JOB-TOKEN: $CI_JOB_TOKEN" \
             --header "Content-Type: application/octet-stream" \
             --header "X-GitLab-Package-Version: latest" \
             --upload-file felmm \
             "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/felm/latest/felm-darwin-amd64"
    fi

    echo "Successfully published binaries to GitLab Package Registry"
    echo "Version: $VERSION and 'latest'"
    return 0
}


function install {

    if isApplicationInstalled "go"; then
        return 0
    fi

    echo "Installing Go..."

    # Detect OS
    local os_type=$(uname -s)

    case "$os_type" in
        "Darwin")  # macOS
            if ! isApplicationInstalled "brew"; then
                echo "Homebrew is required but not installed. Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if [ $? -ne 0 ]; then
                    echo "Failed to install Homebrew"
                    return 1
                fi
            fi

            brew install go
            if [ $? -ne 0 ]; then
                echo "Failed to install Go"
                return 1
            fi
            ;;

        "Linux")
            # Detect distribution
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    "ubuntu"|"debian")
                        sudo apt-get update
                        sudo apt-get install -y golang-go curl
                        ;;
                    "fedora")
                        sudo dnf install -y golang curl
                        ;;
                    "rhel"|"centos")
                        sudo yum install -y golang curl
                        ;;
                    "alpine")
                        apk update
                        apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community go
                        apk add --no-cache curl
                        ;;
                    *)
                        echo "Unsupported Linux distribution: $ID"
                        return 1
                        ;;
                esac

                if [ $? -ne 0 ]; then
                    echo "Failed to install Go"
                    return 1
                fi
            else
                echo "Could not determine Linux distribution"
                return 1
            fi
            ;;

        *)
            echo "Unsupported operating system: $os_type"
            return 1
            ;;
    esac

    # Verify installation
    if ! isApplicationInstalled "go"; then
        echo "Go installation failed"
        return 1
    fi

    echo "Go has been successfully installed"
    echo "Go version: $(go version)"
    return 0
}

function build {
    install
    # create a local tree structure for use with AI Agents
    tree >> ./dir_structure.txt
    echo "###############"
    echo "building felm.."
    echo "###############"
    # export pw="$(read_properties 'LAPTOP')"
    # export gu="$(read_properties 'GITUSERNAME')"
    # export gp="$(read_properties 'GITPASSWORD')"
    # go clean -cache
    go mod tidy
    buildAlpine
    buildLinux
    #buildWindows
    buildMac
    if [ $? -ne 0 ]; then
        echo "Please fix compiliation errors etc."
        exit 1
    fi
}
function download {
    local GITLAB_TOKEN=$(read_properties 'GITPASSWORD')
    # Download using the retrieved version
    curl --header "Private-Token: $GITLAB_TOKEN" \
        "https://mobius-gitlab.bt.com/api/v4/projects/platformservices%2fpocs%2farcam%2ffelm/packages/generic/felm/latest/felm-darwin-amd64" \
        --output felmz
}

function debug {
    install
    # First ensure delve is installed
    if ! isApplicationInstalled "dlv"; then
        echo "Installing Delve debugger..."
        go install github.com/go-delve/delve/cmd/dlv@latest
        if [ $? -ne 0 ]; then
            echo "Failed to install Delve debugger"
            return 1
        fi
    fi

    # Default port if none specified
    local port=${1:-2345}

    # Detect the operating system
    local os_type=$(uname -s)

    echo "Starting debug session on port ${port}..."

    case "$os_type" in
        "Darwin"|"Linux")  # macOS and Linux
            dlv debug ./cmd/main.go --headless --listen=:${port} --api-version=2
            ;;
        *)
            echo "Error: Unsupported operating system for debugging. Amend functions.sh to handle: $os_type"
            return 1
            ;;
    esac
}

