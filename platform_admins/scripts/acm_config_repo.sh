#!/usr/bin/env bash

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

export SCRIPT_DIR=$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null || echo "${PWD}/$(dirname $0)")

mkdir -p ${SCRIPT_DIR}/../../../logs
export LOG_FILE=${SCRIPT_DIR}/../../../logs/acm_config_repo-$(date +%s).log
touch ${LOG_FILE}
exec 2>&1
exec &> >(tee -i ${LOG_FILE})

source ${SCRIPT_DIR}/../scripts/functions.sh
source ${SCRIPT_DIR}/../../../vars.sh

if [[ "${USER_SETUP_RUN,,}" != "true" ]]; then
    echo "Run the user_setup.sh script before executing this script."
    exit 1
fi

declare -A CLOUDS
CLOUDS=(
    ["AWS"]='export EKS_'
    ["AZURE"]='export AKS_'
    ["GCP"]='export GKE_'
)

find ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry -name '*-*' -delete

for CLOUD in "${!CLOUDS[@]}"; do
    echo "Processing ${CLOUD}"
    sed -e s/CLOUD/${CLOUD,,}/ \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/templates/cloud_selector.yaml_tmpl > \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/${CLOUD,,}_selector.yaml
    while IFS= read -r CLUSTER ; do
        ENV_VAR=${CLUSTER%=*}
        ENVIRONMENT=$(awk -F_ '{print tolower($2)}' <<< ${ENV_VAR})

        CLUSTER_NAME=${CLUSTER#*=}

        if [ -z "$CLUSTER_NAME" ]; then
            break
        fi

        echo "Processing ${CLUSTER_NAME}(${ENVIRONMENT})"
        sed -e s/CLUSTER/${CLUSTER_NAME}/ \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/templates/cluster_selector.yaml_tmpl > \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/${CLUSTER_NAME}_selector.yaml

        sed -e s/CLOUD/${CLOUD,,}/ -e s/CLUSTER/${CLUSTER_NAME}/ -e s/ENV/${ENVIRONMENT}/ \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/templates/cluster.yaml_tmpl > \
            ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/${CLUSTER_NAME}.yaml

        if [ ! -f "${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/${ENVIRONMENT}_selector.yaml" ]; then
            sed -e s/ENV/${ENVIRONMENT}/ \
                ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/templates/environment_selector.yaml_tmpl > \
                ${SCRIPT_DIR}/../starter_repos/config_init/clusterregistry/${ENVIRONMENT}_selector.yaml
        fi
    done <<< $(egrep "${CLOUDS[${CLOUD}]}" ${WORKDIR}/vars.sh | sed -e 's/^export //' | sort)
done
