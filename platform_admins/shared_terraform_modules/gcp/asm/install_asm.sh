#!/usr/bin/env bash
# Copyright 2020 Google LLC
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

# issues with EKS hostnames for LB
# https://github.com/istio/istio/issues/29359

# Exit on any error
set -e

# Functions
# ex: retry "command args" 2 10
retry() {
    COMMAND=${1}
    # Default retry count 5
    RETRY_COUNT=${2:-5}
    # Default retry sleep 10s
    RETRY_SLEEP=${3:-10}
    COUNT=1

    while [ ${COUNT} -le ${RETRY_COUNT} ]; do
      ${COMMAND} && break
      echo "### Count ${COUNT}/${RETRY_COUNT} | Failed Command: ${COMMAND}"
      if [ ${COUNT} -eq ${RETRY_COUNT} ]; then
        echo "### Exit Failed: ${COMMAND}"
        exit 1
      fi
      let COUNT=${COUNT}+1
      sleep ${RETRY_SLEEP}
    done
}

# Create bash arrays from lists
IFS=',' read -r -a GKE_LIST <<< "${GKE_LIST_STRING}"
IFS=',' read -r -a GKE_LOC <<< "${GKE_LOC_STRING}"
IFS=',' read -r -a EKS_LIST <<< "${EKS_LIST_STRING}"
IFS=',' read -r -a EKS_INGRESS_IPS <<< "${EKS_INGRESS_IPS_STRING}"
IFS=',' read -r -a EKS_EIP_LIST <<< "${EKS_EIP_LIST_STRING}"
ASM_DIR=istio-${ASM_VERSION}
ASM_CONFIG_DIR=anthos-service-mesh-packages

# asmcli conflicts with PROJECT_ID
export GCP_PROJECT_ID=${PROJECT_ID}
unset PROJECT_ID

# Extract Version
export _MINOR=$(echo ${ASM_VERSION} | cut -d "." -f 2)
export _POINT=$(echo ${ASM_VERSION} | cut -d "." -f 3 | cut -d "-" -f 1)
export _REV=$(echo ${ASM_VERSION} | cut -d "-" -f 2 | cut -d "." -f 2)

# pin to a specific installer - mcp installation inconsistencies
curl https://storage.googleapis.com/csm-artifacts/asm/asmcli_1.${_MINOR} > asmcli
chmod 755 asmcli

# Get ASM
curl -LO https://storage.googleapis.com/gke-release/asm/istio-${ASM_VERSION}-linux-amd64.tar.gz
tar xzf istio-${ASM_VERSION}-linux-amd64.tar.gz
rm -rf istio-${ASM_VERSION}-linux-amd64.tar.gz
export PATH=istio-${ASM_VERSION}/bin:$PATH
ls -l istio-${ASM_VERSION}/samples/certs

# Get ASM Config
git clone -b ${ASM_CONFIG_BRANCH} https://github.com/GoogleCloudPlatform/anthos-service-mesh-packages.git

# Patch kiali to add correct istio config map
sed -i "/^    external_services:$/a\      istio:\n        config_map_name: istio-${ASM_REV_LABEL}\n        istiod_deployment_name: istiod-${ASM_REV_LABEL}\n        istio_sidecar_injector_config_map_name: istio-sidecar-injector-${ASM_REV_LABEL}" \
    ${ASM_DIR}/samples/addons/kiali.yaml

# Create istio-system namespace and certs
kubectl create namespace istio-system --dry-run=client -o yaml > istio-system.yaml

echo -e "${CLUSTER_NETWORK_GATEWAY}" > cluster_network_gateway.yaml
cat cluster_network_gateway.yaml

# Get all EKS clusters' kubeconfig files
for IDX in ${!GKE_LIST[@]}
do
    gcloud container clusters get-credentials ${GKE_LIST[IDX]} --zone ${GKE_LOC[IDX]} --project ${GCP_PROJECT_ID}
done

DEFAULT_KUBECONFIG=${HOME}/.kube/config

for EKS in ${EKS_LIST[@]}
do
    gsutil cp -r gs://$GCP_PROJECT_ID/kubeconfig/kubeconfig_${EKS} .
    KUBECONFIG=${DEFAULT_KUBECONFIG}:kubeconfig_${EKS} kubectl config view --flatten --merge > /tmp/kubeconfig
    cp /tmp/kubeconfig ${DEFAULT_KUBECONFIG}
done

cat ${DEFAULT_KUBECONFIG}
export KUBECONFIG=${DEFAULT_KUBECONFIG}

# prepare istiod-service
cat ${ASM_CONFIG_DIR}/asm/istio/istiod-service.yaml | sed -e s/ASM_REV/${ASM_REV_LABEL}/g > istiod-service.yaml

# patch cross-network-gateway
sed -i '/^      hosts:$/a\        - "*.global"' ${ASM_DIR}/samples/multicluster/expose-services.yaml

# install asm and process secrets
processEKS() {
    EKS=${1}
    EKS_CTX=eks_${EKS}
    exec 1> >(sed "s/^/${EKS} SO: /")
    exec 2> >(sed "s/^/${EKS} SE: /" >&2)

    kubectl --context=${EKS_CTX} get po --all-namespaces
    retry "kubectl --context=${EKS_CTX} apply -f istio-system.yaml"
    # make this declarative later?
    retry "kubectl --context=${EKS_CTX} get namespace istio-system" && \
      retry "kubectl --context=${EKS_CTX} label namespace istio-system topology.istio.io/network=${EKS}-net --overwrite"

    ISTIOD_DEPLOYED=$( { kubectl --context=${EKS_CTX} get deploy -n istio-system istiod-${ASM_REV_LABEL} --no-headers || true; } | wc -l )
    echo "ASM Deployed: " ${ISTIOD_DEPLOYED}
    if [ ! ${ISTIOD_DEPLOYED} == "1" ]; then
        POINT=${_POINT} REV=${_REV} ./asmcli install \
        --fleet_id ${GCP_PROJECT_ID} \
        --kubeconfig ${HOME}/.kube/config \
        --context ${EKS_CTX} \
        --output_dir asm_${EKS_CTX} \
        --platform multicloud \
        --enable_all \
        --ca mesh_ca \
        --custom_overlay asm_${EKS}.yaml
    fi

    # though it's in the IstioOperator, revision label is not honored
    retry "istioctl --context=${EKS_CTX} install -y -f asm_${EKS}-ingressgateway.yaml --revision ${ASM_REV_LABEL}"
    retry "istioctl --context=${EKS_CTX} install -y -f asm_${EKS}-eastwestgateway.yaml --revision ${ASM_REV_LABEL}"
    # install canonical service controller
    retry "kubectl --context=${EKS_CTX} apply -f ${ASM_CONFIG_DIR}/asm/canonical-service/controller.yaml"
    # cluster network gateway
    retry "kubectl --context=${EKS_CTX} apply -f ${ASM_DIR}/samples/multicluster/expose-services.yaml"
    retry "kubectl --context=${EKS_CTX} apply -f istiod-service.yaml"
    retry "kubectl --context=${EKS_CTX} apply -f ${ASM_DIR}/samples/addons/grafana.yaml"
    retry "kubectl --context=${EKS_CTX} apply -f ${ASM_DIR}/samples/addons/prometheus.yaml"
    retry "kubectl --context=${EKS_CTX} apply -f ${ASM_DIR}/samples/addons/kiali.yaml"
    istioctl x create-remote-secret --context=${EKS_CTX} --name ${EKS} > kubeconfig_secret_${EKS}.yaml
}

processGKE() {
    IDX=${1}
    exec 1> >(sed "s/^/${IDX} SO: /")
    exec 2> >(sed "s/^/${IDX} SE: /" >&2)
    GKE_CTX=gke_${GCP_PROJECT_ID}_${GKE_LOC[IDX]}_${GKE_LIST[IDX]}

    kubectl --context=${GKE_CTX} get po --all-namespaces
    retry "kubectl --context=${GKE_CTX} apply -f istio-system.yaml"
    # make this declarative later?
    retry "kubectl --context=${GKE_CTX} get namespace istio-system" && \
      retry "kubectl --context=${GKE_CTX} label namespace istio-system topology.istio.io/network=${GKE_NET} --overwrite"

    ISTIOD_DEPLOYED=$( { kubectl --context=${GKE_CTX} get deploy -n istio-system istiod-${ASM_REV_LABEL} --no-headers || true; } | wc -l )
    echo "ASM Deployed: " ${ISTIOD_DEPLOYED}
    if [ ! ${ISTIOD_DEPLOYED} == "1" ]; then
        POINT=${_POINT} REV=${_REV} ./asmcli install \
        --fleet_id ${GCP_PROJECT_ID} \
        --kubeconfig ${HOME}/.kube/config \
        --context ${GKE_CTX} \
        --output_dir asm_${GKE_CTX} \
        --platform multicloud \
        --enable_all \
        --ca mesh_ca \
        --custom_overlay asm_${GKE_LIST[IDX]}.yaml
    fi

    # though it's in the IstioOperator, revision label is not honored
    retry "istioctl --context=${GKE_CTX} install -y -f asm_${GKE_LIST[IDX]}-ingressgateway.yaml --revision ${ASM_REV_LABEL}" 10 60
    retry "istioctl --context=${GKE_CTX} install -y -f asm_${GKE_LIST[IDX]}-eastwestgateway.yaml --revision ${ASM_REV_LABEL}" 10 60
    # install canonical service controller
    retry "kubectl --context=${GKE_CTX} apply -f ${ASM_CONFIG_DIR}/asm/canonical-service/controller.yaml"
    # cluster network gateway
    retry "kubectl --context=${GKE_CTX} apply -f ${ASM_DIR}/samples/multicluster/expose-services.yaml"
    retry "kubectl --context=${GKE_CTX} apply -f istiod-service.yaml"
    retry "kubectl --context=${GKE_CTX} apply -f ${ASM_DIR}/samples/addons/grafana.yaml"
    retry "kubectl --context=${GKE_CTX} apply -f ${ASM_DIR}/samples/addons/prometheus.yaml"
    retry "kubectl --context=${GKE_CTX} apply -f ${ASM_DIR}/samples/addons/kiali.yaml"
    istioctl x create-remote-secret --context=${GKE_CTX} --name ${GKE_LIST[IDX]} > kubeconfig_secret_${GKE_LIST[IDX]}.yaml
}

for EKS in ${EKS_LIST[@]}
do
    processEKS ${EKS} &
done

# Get GKE credentials
for IDX in ${!GKE_LIST[@]}
do
    processGKE ${IDX} &
done

# wait for all background jobs to finish
wait < <(jobs -p)

# Create cross-cluster service discovery
for EKS in ${EKS_LIST[@]}
do
    echo -e "##### Secrets for ${EKS}... #####\n"
    for EKS_SECRET in ${EKS_LIST[@]}
    do
        if [[ ! $EKS == $EKS_SECRET ]]; then
            echo -e "Creating kubeconfig secret in cluster ${EKS_SECRET} for ${EKS}..."
            retry "kubectl --context=eks_${EKS_SECRET} apply -f kubeconfig_secret_${EKS}.yaml"
        fi
    done
    for GKE_SECRET_IDX in ${!GKE_LIST[@]}
    do
        echo -e "Creating kubeconfig secret in cluster ${GKE_LIST[GKE_SECRET_IDX]} for ${EKS}..."
        GKE_CTX=gke_${GCP_PROJECT_ID}_${GKE_LOC[GKE_SECRET_IDX]}_${GKE_LIST[GKE_SECRET_IDX]}
        retry "kubectl --context=${GKE_CTX} apply -f kubeconfig_secret_${EKS}.yaml"
    done
done

for IDX in ${!GKE_LIST[@]}
do
    echo -e "##### Secrets for ${GKE_LIST[IDX]}... #####\n"
    for EKS_SECRET in ${EKS_LIST[@]}
    do
        echo -e "Creating kubeconfig secret in cluster ${EKS_SECRET} for ${GKE_LIST[IDX]}..."
        retry "kubectl --context=eks_${EKS_SECRET} apply -f kubeconfig_secret_${GKE_LIST[IDX]}.yaml"
    done
    for GKE_SECRET_IDX in ${!GKE_LIST[@]}
    do
        if [[ ! ${GKE_LIST[IDX]} == ${GKE_LIST[GKE_SECRET_IDX]} ]]; then
            echo -e "Creating kubeconfig secret in cluster ${GKE_LIST[GKE_SECRET_IDX]} for ${GKE_LIST[IDX]}..."
            GKE_CTX=gke_${GCP_PROJECT_ID}_${GKE_LOC[GKE_SECRET_IDX]}_${GKE_LIST[GKE_SECRET_IDX]}
            retry "kubectl --context=${GKE_CTX} apply -f kubeconfig_secret_${GKE_LIST[IDX]}.yaml"
        fi
    done
done