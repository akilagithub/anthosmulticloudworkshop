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


# Create arrays from inputed strings
IFS=',' read -r -a GKE_LIST <<< "${GKE_LIST_STRING}"
IFS=',' read -r -a GKE_LOC <<< "${GKE_LOC_STRING}"
IFS=',' read -r -a EKS_LIST <<< "${EKS_LIST_STRING}"
IFS=',' read -r -a EKS_INGRESS_IPS <<< "${EKS_INGRESS_IPS_STRING}"
IFS=',' read -r -a EKS_EIP_LIST <<< "${EKS_EIP_LIST_STRING}"


##### CREATE GKE YAMLs
# Start the YAML file
for GKE in ${GKE_LIST[@]}
do
    echo -e "Building file for $GKE..."
    echo -e "${HEADER}" | sed -e s/ASM_REV_LABEL/${ASM_REV_LABEL}/g > asm_$GKE.yaml

    # Disabled ingress gateway
    echo -e "${GATEWAY_COMPONENT}" >> asm_$GKE.yaml

    # Add meshconfig
    echo -e "${GKE_MESHCONFIG}" >> asm_$GKE.yaml

    # Add values
    echo -e "${GCP_VALUES}" | sed -e s/GKE/$GKE/g -e s/GCP_NET/$GKE_NET/g -e s/MESH_ID/proj-$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_$GKE.yaml

    # Add registries
    for GKE_NAME in ${GKE_LIST[@]}
    do
       echo -e "$GCP_REGISTRY" | sed -e s/GKE/$GKE_NAME/g >> asm_$GKE.yaml
    done

    # Add GCP bottom
    echo -e "$GATEWAYS_REGISTRY" >> asm_$GKE.yaml

    # Add EKS cluster sections
    for IDX in ${!EKS_LIST[@]}
    do
        let INGRESS_IP_IDX="($IDX + 1) * 2 - 2"
        echo -e "${EKS_REMOTE_NETWORK}" | sed -e s/EKS/${EKS_LIST[IDX]}/g -e \
        s/ISTIOINGRESS_IP/${EKS_INGRESS_IPS[INGRESS_IP_IDX]}/g >> asm_$GKE.yaml
    done

    # Ingress gateway
    echo -e "${HEADER_EMPTY}" | sed -e s/ASM_REV_LABEL/${ASM_REV_LABEL}/g > asm_$GKE-ingressgateway.yaml
    echo -e "${GKE_COMPONENT}" | sed -e s/ENV/$ENV/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_$GKE-ingressgateway.yaml
    echo -e "${GATEWAY_VALUES}" | sed -e s/CLUSTER_NAME/$GKE/g -e s/MESH_NETWORK/$GKE_NET/g -e s/PROJECT_NUMBER/$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_$GKE-ingressgateway.yaml

    # East West Gateway
    echo -e "${EASTWESTGATEWAY_GKE}" | sed -e s/MESH_NETWORK/$GKE_NET/g -e s/ASM_REV_LABEL/$ASM_REV_LABEL/g -e s/PROJECT_ID/$PROJECT_ID/g > asm_$GKE-eastwestgateway.yaml
    echo -e "${GATEWAY_VALUES}" | sed -e s/CLUSTER_NAME/$GKE/g -e s/MESH_NETWORK/$GKE_NET/g -e s/PROJECT_NUMBER/$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_$GKE-eastwestgateway.yaml
done

##### CREATE EKS YAMLs
# Start the YAML file
for EKS_IDX in ${!EKS_LIST[@]}
do
    echo -e "Building file for ${EKS_LIST[EKS_IDX]}..."
    echo -e "${HEADER}" | sed -e s/ASM_REV_LABEL/${ASM_REV_LABEL}/g > asm_${EKS_LIST[EKS_IDX]}.yaml

    # Add istio ingress gateway annotations to get EIPs
    let EIP_IDX_1="($EKS_IDX + 1) * 2 - 2"
    let EIP_IDX_2="($EKS_IDX + 1) * 2 - 1"

    echo -e "Ingress IP List: ${EKS_INGRESS_IPS}"

    # echo -e "for ${EKS_LIST[EKS_IDX]}, the first EIP index is $EIP_IDX_1"
    # echo -e "for ${EKS_LIST[EKS_IDX]}, the second EIP index is $EIP_IDX_2"

    # Disabled ingress gateway
    echo -e "${GATEWAY_COMPONENT}" >> asm_${EKS_LIST[EKS_IDX]}.yaml

    # Add meshconfig
    echo -e "${EKS_MESHCONFIG}" | sed -e s/EKS/${EKS_LIST[EKS_IDX]}/g -e s/PROJECT_ID/$PROJECT_ID/g -e s/CLUSTER_LOCATION/us-west1/g >> asm_${EKS_LIST[EKS_IDX]}.yaml

    # Add values
    echo -e "${EKS_VALUES}" | sed -e s/EKS/${EKS_LIST[EKS_IDX]}/g -e s/GCP_NET/$GKE_NET/g -e s/MESH_ID/proj-$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_${EKS_LIST[EKS_IDX]}.yaml

    # Add registries
    for GKE_NAME in ${GKE_LIST[@]}
    do
        echo -e "${GCP_REGISTRY}" | sed -e s/GKE/$GKE_NAME/g >> asm_${EKS_LIST[EKS_IDX]}.yaml
    done

    # Add GCP bottom
    echo -e "${GATEWAYS_REGISTRY}" >> asm_${EKS_LIST[EKS_IDX]}.yaml

    # Add EKS cluster sections
    for IDX in ${!EKS_LIST[@]}
    do
        if [[ $EKS_IDX == $IDX ]]; then
            echo -e "Building network patch for ${EKS_LIST[EKS_IDX]} and small IDX is $IDX"
            echo -e "${EKS_SELF_NETWORK}" | sed -e s/EKS/${EKS_LIST[IDX]}/g \
            >> asm_${EKS_LIST[EKS_IDX]}.yaml
        else
            echo -e "Building network patch for ${EKS_LIST[EKS_IDX]} and small IDX is $IDX"
            let INGRESS_IP_IDX="($IDX + 1) * 2 - 2"
            echo -e "${EKS_REMOTE_NETWORK}" | sed -e s/EKS/${EKS_LIST[IDX]}/g -e \
            s/ISTIOINGRESS_IP/${EKS_INGRESS_IPS[INGRESS_IP_IDX]}/g \
            >> asm_${EKS_LIST[EKS_IDX]}.yaml
        fi
    done
    
    # Ingress gateway
    echo -e "${HEADER_EMPTY}" | sed -e s/ASM_REV_LABEL/${ASM_REV_LABEL}/g > asm_${EKS_LIST[EKS_IDX]}-ingressgateway.yaml
    echo -e "${EKS_COMPONENT}" | sed -e s/PROJECT_ID/$PROJECT_ID/g -e s/CLUSTER_NAME/${EKS_LIST[EKS_IDX]}/g >> asm_${EKS_LIST[EKS_IDX]}-ingressgateway.yaml  
    echo -e "${GATEWAY_VALUES}" | sed -e s/CLUSTER_NAME/${EKS_LIST[EKS_IDX]}/g -e s/MESH_NETWORK/${EKS_LIST[EKS_IDX]}-net/g -e s/PROJECT_NUMBER/$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_${EKS_LIST[EKS_IDX]}-ingressgateway.yaml

    # East West Gateway
    echo -e "${EASTWESTGATEWAY_EKS}" | sed -e s/MESH_NETWORK/${EKS_LIST[EKS_IDX]}-net/g -e s/ASM_REV_LABEL/$ASM_REV_LABEL/g -e s/PROJECT_ID/$PROJECT_ID/g -e s/CLUSTER_NAME/${EKS_LIST[EKS_IDX]}/g > asm_${EKS_LIST[EKS_IDX]}-eastwestgateway.yaml
    echo -e "${GATEWAY_VALUES}" | sed -e s/CLUSTER_NAME/${EKS_LIST[EKS_IDX]}/g -e s/MESH_NETWORK/${EKS_LIST[EKS_IDX]}-net/g -e s/PROJECT_NUMBER/$PROJECT_NUMBER/g -e s/PROJECT_ID/$PROJECT_ID/g >> asm_${EKS_LIST[EKS_IDX]}-eastwestgateway.yaml

    # patch with nlb for EKS
    sed -i "/^        k8s:$/a\          service_annotations:\n            service.beta.kubernetes.io/aws-load-balancer-type: nlb\n            service.beta.kubernetes.io/aws-load-balancer-eip-allocations: \"${EKS_EIP_LIST[EIP_IDX_1]},${EKS_EIP_LIST[EIP_IDX_2]}\"" asm_${EKS_LIST[EKS_IDX]}-eastwestgateway.yaml
done

for GKE in ${GKE_LIST[@]}
do
    echo -e "\n######### $GKE YAML ###########\n"
    cat asm_$GKE.yaml
    gsutil cp -r asm_$GKE.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_$GKE.yaml
    
    echo -e "\n######### $GKE ingressgateway YAML ###########\n"
    cat asm_${GKE}-ingressgateway.yaml
    gsutil cp -r asm_${GKE}-ingressgateway.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_${GKE}-ingresssgateway.yaml

    echo -e "\n######### $GKE eastwestgateway YAML ###########\n"
    cat asm_${GKE}-eastwestgateway.yaml
    gsutil cp -r asm_${GKE}-eastwestgateway.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_${GKE}-eastwestgateway.yaml
done

for EKS in ${EKS_LIST[@]}
do
    echo -e "\n######### $EKS YAML ###########\n"
    cat asm_$EKS.yaml
    gsutil cp -r asm_$EKS.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_$EKS.yaml

    echo -e "\n######### $EKS ingressgateway YAML ###########\n"
    cat asm_${EKS}-ingressgateway.yaml
    gsutil cp -r asm_${EKS}-ingressgateway.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_${EKS}-ingressgateway.yaml
    
    echo -e "\n######### $EKS eastwestgateway YAML ###########\n"
    cat asm_${EKS}-eastwestgateway.yaml
    gsutil cp -r asm_${EKS}-eastwestgateway.yaml gs://$PROJECT_ID/asm_istiooperator_cr/asm_${EKS}-eastwestgateway.yaml
done
