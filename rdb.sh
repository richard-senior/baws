#!/bin/bash

########################################################################
### AURORA           ###################################################
########################################################################

function isDbSubnetGroupExists {

    if [ -z "$AURORA_CLUSTER_NAME" ]; then
        if [ -z "$1" ]; then
            echo "you must supply cluster name as first parameter"
            return 1
        fi
        export AURORA_CLUSTER_NAME="$1"
    fi

    local sgname="$AURORA_CLUSTER_NAME-subnet-group"

    aws --profile $PROFILE --region $REGION rds describe-db-subnet-groups --db-subnet-group-name "$sgname" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function createDbSubnetGroup {
    # debug if necessary
    # bawsDebug

    if [ -z "$AURORA_CLUSTER_NAME" ]; then
        if [ -z "$1" ]; then
            echo "you must supply cluster name as first parameter"
            return 1
        fi
        export AURORA_CLUSTER_NAME="$1"
    fi

    local sgname="$AURORA_CLUSTER_NAME-subnet-group"

    if isDbSubnetGroupExists; then
        echo "DB Subnet Group '$1' already exists. Nothing to do."
        return
    fi

    echo "Getting private subnets for platform"
    SUBNETS="$(getSpaceDelimitedPrivateSubnetsForPlatform)"

    if [ -z "$SUBNETS" ]; then
        echo "No subnets found for platform '$PLATFORM' (VPC $VPCID). Cannot create DB Subnet Group."
        return
    fi

    echo "Creating subnet group of private subnets"
    aws --profile $PROFILE --region $REGION rds create-db-subnet-group \
        --db-subnet-group-name "$sgname" \
        --db-subnet-group-description "Subnet group for the aurora DB that backs devlake" \
        --subnet-ids "$SUBNETS" \
        --tags $(getTagsRaw "$sgname")

    if [ $? -ne 0 ]; then
        echo "failed to create subnet group"
        return 1
    else
        echo "subnet group created"
    fi
}

# Creates an IAM role for an aurora cluster
# if the env variable AURORA_CLUSTER_NAME is populated
# this is used to form the various names (role name, policy name) etc.
# otherwise you must pass the cluster name in $1
# The cluster must already exist before this function is called
# Also creates a policy and associates the role with the cluster
# if the role already exists, then nothing is done
function create_aurora_iam_role {

    if [ -z "$AURORA_CLUSTER_NAME" ]; then
        if [ -z "$1" ]; then
            echo "you must supply cluster name as first parameter"
            return
        fi
        export AURORA_CLUSTER_NAME="$1"
    fi

    local roleName="$AURORA_CLUSTER_NAME-role"

    if ! roleExists "$roleName"; then
        echo "Creating IAM role for aurora cluster"ju`w`x1  s
        # Create the IAM role
        local roleArn=$(aws --profile $PROFILE --region $REGION iam create-role \
            --role-name "$roleName" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "rds.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' \
            --query "Role.Arn" \
            --output text 2>/dev/null)

        if [ -z "$roleArn" ]; then
            echo "failed to get role arn for role '$roleName'"
            return 1
        fi
    fi

    local arn=$(getAuroraClusterArn)

    local pn="$AURORA_CLUSTER_NAME-policy"

    if ! policyExists "$pn"; then
        # Create the IAM policy
        local policyArn=$(aws --profile $PROFILE --region $REGION create-policy \
            --policy-name "$pn" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "rds-db:connect"
                        ],
                        "Resource": [
                            "'"$arn"'"
                        ]
                    }
                ]
            }' \
            --query "Policy.Arn" \
            --output text 2>/dev/null)

        if [ -z "$policyArn" ]; then
            local policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='$pn'].Arn" --output text)
        fi

        if [ -z "$policyArn" ]; then
            echo "failed to get policy arn for policy '$pn'"
            return 1
        fi
        # Attach the policy to the role
        aws iam attach-role-policy \
            --role-name "$roleName" \
            --policy-arn "$policyArn"

        echo "IAM role '$roleName' created and policy '$policyArn' attached successfully."
    fi

    # Associate the role with the cluster
    # this will do nothing if the role is already associated
    aws --profile $PROFILE --region $REGION rds add-role-to-db-cluster --db-cluster-identifier "$AURORA_CLUSTER_NAME" --role-arn "$roleArn"
}

# Attempts to find and echo the arn of the aurora cluster
# the env variable AURORA_CLUSTER_ARN is then populated
# If the env variable AURORA_CLUSTER_NAME is populated this is used
# otherwise must pass the cluster name as $1
function getAuroraClusterArn {

    if [ ! -z "$AURORA_CLUSTER_ARN" ]; then
        echo "$AURORA_CLUSTER_ARN"
        return 0
    fi

    if [ -z "$AURORA_CLUSTER_NAME" ]; then
        if [ -z "$1" ]; then
            echo "you must supply cluster name as first parameter"
            return
        fi
        export AURORA_CLUSTER_NAME="$1"
    fi
    local arn=$(aws --profile $PROFILE --region $REGION rds describe-db-clusters --query "DBClusters[?DatabaseName=='$AURORA_CLUSTER_NAME'].DBClusterArn" --output text 2>/dev/null)
    if [ $? -ne 0 ]; then return 1; fi
    if [ -z "$arn" ]; then return 1; fi
    export AURORA_CLUSTER_ARN="$arn"
    echo "$arn"
    return 0
}

########################################################################
### GENERAL        #####################################################
########################################################################

# useful for deciding which mysql version to use in Aurora
function listDbEnginVersions {
    aws --profile $PROFILE --region $REGION rds describe-db-engine-versions --engine aurora-mysql --query "DBEngineVersions[].EngineVersion"
    # aws rds describe-db-engine-versions --engine mysql --query "DBEngineVersions[].EngineVersion"
}
########################################################################
### VPC AND SUBNETS     ################################################
########################################################################

function getDbSecurityGroupId {
    echo "$(getSgId $AURORA_SG_NAME)"
}

function createDbClusterSecurityGroup {
    local sg_description="Security group for VPC DevLake configuration"

    if [ -z "$AURORA_CLUSTER_NAME" ]; then
        if [ -z "$1" ]; then
            echo "you must supply cluster name as first parameter"
            return
        fi
        export AURORA_CLUSTER_NAME="$1"
    fi

    local AURORA_SG_NAME="$AURORA_CLUSTER_NAME-sg"

    if isSgExists $AURORA_SG_NAME; then
        echo "ECS Security Group $AURORA_SG_NAME already exists"
        return 0
    fi

    local VPCID=$(getVpcId)

    echo "Creating ECS Security Group $AURORA_SG_NAME for VPC $VPCID"
    local sg_id=$(aws --profile $PROFILE --region $REGION ec2 create-security-group \
        --group-name "$AURORA_SG_NAME" \
        --description "$sg_description" \
        --vpc-id "$VPCID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$AURORA_SG_NAME},{Key=platform-name,Value=$PLATFORM_NAME},{Key=stack-name,Value=$STACK_NAME}]" \
        --query "GroupId" \
        --output text
    )
    if [ $? -ne 0 ]; then
        echo "Failed to create ECS Security Group $AURORA_SG_NAME"
        return 1
    fi
    if [ -z "$sg_id" ]; then
        echo "Failed to create ECS Security Group $AURORA_SG_NAME"
        return 1
    fi

    # TODO ingress rules for ECS etc.
    echo "DB Security Group ID: $sg_id"
}

########################################################################
### Parameter Groups     ###############################################
########################################################################

function isDbClusterParameterGroupExists {
    aws --profile $PROFILE --region $REGION rds describe-db-cluster-parameter-groups \
        --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME" &>/dev/null
    return $?
}

function deleteDbClusterParameterGroup {

    if ! isDbClusterParameterGroupExists; then
        echo "DB cluster parameter group '$DB_PARAMETER_GROUP_NAME' does not exist. No action needed."
        return 0
    fi

    aws --profile "$PROFILE" --region "$REGION" rds delete-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME"

    if [ $? -eq 0 ]; then
        echo "DB cluster parameter group '$DB_PARAMETER_GROUP_NAME' deleted successfully."
        return 0
    else
        echo "Failed to delete DB cluster parameter group '$DB_PARAMETER_GROUP_NAME'."
        return 1
    fi
}

function createDbClusterParameterGroup {
    local description="Custom parameter group for $DB_CLUSTER_NAME"

    if isDbClusterParameterGroupExists; then
        echo "DB cluster parameter group '$DB_PARAMETER_GROUP_NAME' already exists."
        return
    fi
    # Create the DB cluster parameter group
    aws --profile $PROFILE --region $REGION rds create-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME" \
        --db-parameter-group-family "$DB_PARAMETER_GROUP_FAMILY" \
        --description "$description" \
        --tags "Key=platform-name,Value=$PLATFORM_NAME" "Key=stack-name,Value=$STACK_NAME"

    if [ $? -eq 0 ]; then
        echo "DB cluster parameter group '$DB_PARAMETER_GROUP_NAME' created successfully."

        # Optionally, you can modify parameters here
        # For example:
        # aws --profile $PROFILE --region $REGION rds modify-db-cluster-parameter-group \
        #     --db-cluster-parameter-group-name "$parameter_group_name" \
        #     --parameters "ParameterName=max_connections,ParameterValue=1000,ApplyMethod=pending-reboot"

        return 0
    else
        echo "Failed to create DB cluster parameter group '$DB_PARAMETER_GROUP_NAME'."
        return 1
    fi
}

########################################################################
### Aurora               ###############################################
########################################################################

function getDbClusterEndpoint {
    local foo=$(aws --profile $PROFILE --region $REGION rds describe-db-clusters --query '*[0].{Endpoint:Endpoint}' --output text 2>/dev/null)
    if [ ! -z "$foo" ]; then
        echo "$foo"
    fi
}

function isDbClusterExists {
    local cluster_name=$DB_CLUSTER_NAME
    aws --profile $PROFILE --region $REGION rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_NAME" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function doDestroyDbCluster {
    if ! isDbClusterExists; then
        echo "DB cluster '$DB_CLUSTER_NAME' does not exist. Nothing to do."
        return
    fi
    echo "deleting db cluster $DB_CLUSTER_NAME"
    # Check if deletion protection is enabled
    # aws --profile non-production --region eu-west-1 rds describe-db-clusters --db-cluster-identifier devlakedb --query 'DBClusters[0].DeletionProtection' --output text
    local p=$(aws --profile $PROFILE --region $REGION rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_NAME" --query 'DBClusters[0].DeletionProtection' --output text)

    if [ ! -z "$p" ] && [ "$p"=="True" ]; then
        echo "Deletion protection is enabled. Disabling it first..."
        aws --profile $PROFILE --region $REGION rds modify-db-cluster \
            --db-cluster-identifier "$DB_CLUSTER_NAME" \
            --no-deletion-protection

        if [ $? -ne 0 ]; then
            echo "Failed to disable deletion protection. Aborting deletion."
            return 1
        fi
        echo "Deletion protection disabled."
    fi

    # Attempt to delete the cluster
    aws --profile $PROFILE --region $REGION rds delete-db-cluster \
        --db-cluster-identifier "$DB_CLUSTER_NAME" \
        --skip-final-snapshot

    if [ $? -eq 0 ]; then
        echo "DB cluster deletion initiated for '$DB_CLUSTER_NAME'. Waiting for deletion to complete..."

        # Wait for the cluster to be deleted
        aws --profile "$PROFILE" --region "$REGION" rds wait db-cluster-deleted --db-cluster-identifier "$DB_CLUSTER_NAME"

        if [ $? -eq 0 ]; then
            echo "DB cluster '$DB_CLUSTER_NAME' deleted successfully."
            return 0
        else
            echo "Timeout waiting for DB cluster '$DB_CLUSTER_NAME' to be deleted. Please check the AWS console for status."
            return 1
        fi
    else
        echo "Failed to initiate deletion of DB cluster '$DB_CLUSTER_NAME'."
        return 1
    fi
}

function doCreateDbCluster {
    if isDbClusterExists; then
        echo "DB cluster '$DB_CLUSTER_NAME' already exists."
        return
    fi
    # it turns out that this might not be necessary
    #local sgid=$(getSgId $AURORA_SG_NAME)
    #if [ -z "$sgid" ]; then
    #    echo "Security group '$AURORA_SG_NAME' does not exist. Please create it first."
    #    return
    #fi
    local sgid=$(getSgId $AURORA_SG_NAME)
    echo "Creating DB cluster '$DB_CLUSTER_NAME' with security group '$AURORA_SG_NAME' with engine version '$ENGINE_VERSION'"
    local foo=$(aws --profile $PROFILE --region $REGION rds create-db-cluster \
        --db-cluster-identifier "$DB_CLUSTER_NAME" \
        --engine aurora-mysql \
        --serverless-v2-scaling-configuration MinCapacity=1,MaxCapacity=4 \
        --engine-version "$ENGINE_VERSION" \
        --engine-mode provisioned \
        --master-username "$USERNAME" \
        --master-user-password "$SECURE_PASSWORD" \
        --db-subnet-group-name "$DB_SUBNET_NAME" \
        --db-cluster-parameter-group-name "$DB_PARAMETER_GROUP_NAME" \
        --vpc-security-group-ids "$sgid" \
        --enable-http-endpoint \
        --backup-retention-period 7 \
        --preferred-backup-window "02:00-03:00" \
        --preferred-maintenance-window "sun:05:00-sun:06:00" \
        --deletion-protection \
        --enable-cloudwatch-logs-exports '["error","general","slowquery","audit"]' \
        --copy-tags-to-snapshot \
        --tags "Key=platform-name,Value=$PLATFORM_NAME" "Key=stack-name,Value=$STACK_NAME" \
        --query "DBCluster.DBClusterArn" \
        --output text
    )

    if [ $? -eq 0 ]; then
        echo "DB cluster creation initiated for '$DB_CLUSTER_NAME'. Waiting for it to become available..."

       # Wait for the cluster to become available
        aws --profile "$PROFILE" --region "$REGION" rds wait db-cluster-available --db-cluster-identifier "$DB_CLUSTER_NAME"

        if [ $? -eq 0 ]; then
            echo "DB cluster '$DB_CLUSTER_NAME' is now available."
            DB_CLUSTER_ARN="$foo"
            echo "arn is $foo"
            return 0
        else
            echo "Timeout waiting for DB cluster '$DB_CLUSTER_NAME' to become available. Please check the AWS console for status."
            return 1
        fi
    else
        echo "Failed to initiate creation of DB cluster '$DB_CLUSTER_NAME'."
        return 1
    fi

    #--kms-key-id "$KMS_KEY_ALIAS"
    #--storage-encrypted
    #--scaling-configuration "MinCapacity=2,MaxCapacity=4,AutoPause=false,TimeoutAction=ForceApplyCapacityChange"
}

function getAuroraClusterEndpoint {
    local foo=$(aws --profile $PROFILE --region $REGION rds describe-db-cluster-endpoints \
        --db-cluster-identifier $AURORA_CLUSTER_NAME --query "DBClusterEndpoints[0].Endpoint" --output text 2>/dev/null
    )
    if [ ! -z "foo" ]; then
       echo "$foo"
    fi
}

function isDbInstanceExists {
    aws --profile $PROFILE --region $REGION rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_NAME" &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function createDbInstance {
    if isDbInstanceExists; then
        echo "DB instance '$DB_INSTANCE_NAME' already exists."
        return 0
    fi

    echo "Creating DB instance '$DB_INSTANCE_NAME'..."
    aws --profile "$PROFILE" --region "$REGION" rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_NAME" \
        --db-cluster-identifier "$DB_CLUSTER_NAME" \
        --engine aurora-mysql \
        --engine-version "$ENGINE_VERSION" \
        --db-instance-class db.serverless \
        #--db-parameter-group-name "$DB_PARAMETER_GROUP_NAME" \
        --tags Key=platform-name,Value=$PLATFORM_NAME Key=stack-name,Value=$STACK_NAME

    if [ $? -eq 0 ]; then
        echo "DB instance creation initiated for '$DB_INSTANCE_NAME'. Waiting for it to become available..."

        # Wait for the instance to become available
        aws --profile "$PROFILE" --region "$REGION" rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_NAME"

        if [ $? -eq 0 ]; then
            echo "DB instance '$DB_INSTANCE_NAME' is now available."
            return 0
        else
            echo "Timeout waiting for DB instance '$DB_INSTANCE_NAME' to become available. Please check the AWS console for status."
            return 1
        fi
    else
        echo "Failed to initiate creation of DB instance '$DB_INSTANCE_NAME'."
        return 1
    fi
}

function deleteDbInstance {
    if ! isDbInstanceExists; then
        echo "DB instance '$DB_INSTANCE_NAME' does not exist. Nothing to delete."
        return 0
    fi

    echo "Deleting DB instance '$DB_INSTANCE_NAME'..."
    aws --profile "$PROFILE" --region "$REGION" rds delete-db-instance \
        --db-instance-identifier "$DB_INSTANCE_NAME" \
        --skip-final-snapshot

    if [ $? -eq 0 ]; then
        echo "DB instance deletion initiated for '$DB_INSTANCE_NAME'. Waiting for deletion to complete..."

        # Wait for the instance to be deleted
        aws --profile "$PROFILE" --region "$REGION" rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_NAME"

        if [ $? -eq 0 ]; then
            echo "DB instance '$DB_INSTANCE_NAME' deleted successfully."
            return 0
        else
            echo "Timeout waiting for DB instance '$DB_INSTANCE_NAME' to be deleted. Please check the AWS console for status."
            return 1
        fi
    else
        echo "Failed to initiate deletion of DB instance '$DB_INSTANCE_NAME'."
        return 1
    fi
}

function assertMysqlInstalled {
    if command -v mysql &> /dev/null; then
        echo "MySQL client is already installed."
        return 0
    fi

    echo "MySQL client is not installed. Attempting to install..."

    # Detect the operating system
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command -v brew &> /dev/null; then
            echo "Homebrew is required to install MySQL client on macOS. Please install Homebrew first."
            return 1
        fi
        brew install mysql-client
        if [ $? -ne 0 ]; then
            echo "Failed to install MySQL client via Homebrew."
            return 1
        fi
        echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.bash_profile
        source ~/.bash_profile
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
            # Debian/Ubuntu
            sudo apt-get update
            sudo apt-get install -y mysql-client
        elif command -v yum &> /dev/null; then
            # CentOS/RHEL
            sudo yum install -y mysql
        elif command -v dnf &> /dev/null; then
            # Fedora
            sudo dnf install -y mysql
        else
            echo "Unsupported Linux distribution. Please install MySQL client manually."
            return 1
        fi
    else
        echo "Unsupported operating system. Please install MySQL client manually."
        return 1
    fi

    if command -v mysql &> /dev/null; then
        echo "MySQL client has been successfully installed."
        return 0
    else
        echo "Failed to install MySQL client. Please install it manually."
        return 1
    fi
}


function deleteLakeDatabase {
    local endpoint=$(getAuroraClusterEndpoint)
    if [ -z "$endpoint" ]; then
        echo "Failed to get Aurora cluster endpoint. Exiting."
        return 1
    fi

    assertMysqlInstalled

    echo "Deleting 'lake' database from Aurora cluster..."

    # Create a temporary MySQL config file
    local temp_config=$(mktemp)
    cat << EOF > "$temp_config"
[client]
user=$USERNAME
password=$SECURE_PASSWORD
host=$endpoint
EOF

    # Delete the 'lake' database
    mysql --defaults-file="$temp_config" << EOF
DROP DATABASE IF EXISTS lake;
EOF

    local mysql_exit_status=$?

    # Remove the temporary config file
    rm -f "$temp_config"

    if [ $mysql_exit_status -eq 0 ]; then
        echo "'lake' database deleted successfully."
        return 0
    else
        echo "Failed to delete 'lake' database. Please check your Aurora cluster configuration and try again."
        return 1
    fi
}

function createLakeDb {
    # TODO this method will not work unless aurora is opened up via nat gateway etc.
    echo "You must now access the aurora cluster via aws console and run the following SQL:"
    echo "CREATE DATABASE IF NOT EXISTS lake CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
    echo "ALTER DATABASE lake CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
    return 0

    local endpoint=$(getAuroraClusterEndpoint)
    if [ -z "$endpoint" ]; then
        echo "Failed to get Aurora cluster endpoint. Exiting."
        return 1
    fi

    assertMysqlInstalled

    echo "Setting up DevLake database on Aurora cluster..."
    echo "Trying to connect on $endpoint"

    # Create a temporary MySQL config file
    local temp_config=$(mktemp)
    cat << EOF > "$temp_config"
[client]
user=$USERNAME
password=$SECURE_PASSWORD
host=$endpoint
EOF
    # Create the 'lake' database and set character set and collation
    mysql --defaults-file="$temp_config" << EOF
CREATE DATABASE IF NOT EXISTS lake CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
ALTER DATABASE lake CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;

-- Set global character set and collation
SET GLOBAL character_set_server = utf8mb4;
SET GLOBAL collation_server = utf8mb4_bin;

-- Verify settings
SELECT @@character_set_server, @@collation_server;
SHOW VARIABLES LIKE 'character_set_database';
SHOW VARIABLES LIKE 'collation_database';
EOF

    local mysql_exit_status=$?

    # Remove the temporary config file
    rm -f "$temp_config"

    if [ $mysql_exit_status -eq 0 ]; then
        echo "DevLake database setup completed successfully."
        return 0
    else
        echo "Failed to set up DevLake database. Please check your Aurora cluster configuration and try again."
        return 1
    fi
}

########################################################################
### compound functions    ##############################################
########################################################################




