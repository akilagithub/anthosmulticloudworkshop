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

# Styles
BOLD=$(tput bold)
NORMAL=$(tput sgr0)

# Colors
CYAN='\033[1;36m'
GREEN='\e[1;32m'
RED='\e[1;91m'
RESET='\e[0m'
YELLOW="\e[38;5;226m"

function echo_bold {
    echo "${BOLD}${@}${NORMAL}"
}

function echo_heading {
    echo
    echo_bold "${@}"
}

if [[ ! $USER_SETUP_RUN ]]; then
    echo "The user_setup.sh script must be run before executing this script"
    echo "source ${WORKDIR}/anthos-multicloud-workshop/user_setup.sh"
    exit -1
fi

echo_bold "Cleaning up Production resources"

if gcloud compute networks describe prod-gcp-vpc-01 &>/dev/null; then
    # Cleanup all Google Cloud resources
    GKE_CLUSTERS=(${GKE_PROD_1} ${GKE_PROD_2})

    echo_heading "[Google] Unregistering clusters"
    for cluster in "${GKE_CLUSTERS[@]}"; do
        if gcloud container hub memberships describe ${cluster} &>/dev/null; then
            echo "         - Unregistering cluster '${cluster}'"
            gcloud container hub memberships delete ${cluster} --quiet
        fi
    done

    echo_heading "[Google] Deleting clusters"
    if gcloud container clusters describe ${GKE_PROD_1} --zone us-west2-a &>/dev/null; then
        echo "         - Deleting cluster '${GKE_PROD_1}'"
        gcloud container clusters delete ${GKE_PROD_1} --quiet --zone us-west2-a
    fi

    if gcloud container clusters describe ${GKE_PROD_2} --zone us-west2-b &>/dev/null; then
        echo "         - Deleting cluster '${GKE_PROD_1}'"
        gcloud container clusters delete ${GKE_PROD_2} --quiet --zone us-west2-b
    fi

    echo_heading "[Google] Deleting firewall rules"
    for firewall_rule in $(gcloud compute firewall-rules list --filter network:prod-gcp-vpc-01 --format="value(name)" 2>/dev/null); do
        echo "         - Deleting firewall rule '${firewall_rule}'"
        gcloud compute firewall-rules delete ${firewall_rule} --quiet
    done

    echo_heading "[Google] Deleting NEGs"
    for neg in $(gcloud compute network-endpoint-groups list --filter network:prod-gcp-vpc-01 --format="value(name)" --zones us-west2-a 2>/dev/null); do
        echo "         - Deleting NEG '${neg}'"
        gcloud compute network-endpoint-groups delete ${neg} --quiet --zone us-west2-a
    done

    for neg in $(gcloud compute network-endpoint-groups list --filter network:prod-gcp-vpc-01 --format="value(name)" --zones us-west2-b 2>/dev/null); do
        echo "         - Deleting NEG '${neg}'"
        gcloud compute network-endpoint-groups delete ${neg} --quiet --zone us-west2-b
    done

    echo_heading "[Google] Deleting subnets"
    if gcloud compute networks subnets describe prod-gcp-vpc-01-us-west2-subnet-01 --region us-west2 &>/dev/null; then
        echo "         - Deleting subnet 'prod-gcp-vpc-01-us-west2-subnet-01'"
        gcloud compute networks subnets delete prod-gcp-vpc-01-us-west2-subnet-01 --quiet --region us-west2
    fi

    if gcloud compute networks subnets describe prod-gcp-vpc-01-us-east4-subnet-02 --region=us-east4 &>/dev/null; then
        echo "         - Deleting subnet 'prod-gcp-vpc-01-us-east4-subnet-02'"
        gcloud compute networks subnets delete prod-gcp-vpc-01-us-east4-subnet-02 --quiet --region us-east4
    fi

    echo_heading "[Google] Deleting VPC"
    if gcloud compute networks describe prod-gcp-vpc-01 &>/dev/null; then
        echo "         - Deleting VPC 'prod-gcp-vpc-01'"
        gcloud compute networks delete prod-gcp-vpc-01 --quiet
    fi
fi

AWS_REGION="us-west-2"
VPC_ID=$(aws ec2 describe-vpcs --filter Name=tag:Name,Values=aws-vpc-prod --region ${AWS_REGION} --query Vpcs[0].VpcId --output text)
if [[ ${VPC_ID} != "None" ]]; then
    # Cleanup all AWS resources
    EKS_CLUSTERS=(${EKS_PROD_1} ${EKS_PROD_2}) 

    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C ${HOME}/bin

    echo_heading "[AWS] Unregistering clusters"
    for cluster in "${EKS_CLUSTERS[@]}"; do
        if gcloud container hub memberships describe ${cluster} &>/dev/null; then
            echo "      - Unregistering cluster '${cluster}'"
            gcloud container hub memberships delete ${cluster} --quiet
        fi
    done

    echo_heading "[AWS] Deleting clusters"
    for cluster in ${EKS_CLUSTERS[@]}; do
        if eksctl get cluster --name ${cluster} --region ${AWS_REGION} &>/dev/null; then
            echo "      - Deleting cluster '${cluster}'"
            kubectl --context ${cluster} delete services --all
            eksctl delete cluster --name ${cluster} --region ${AWS_REGION}
        fi
    done

    echo_heading "[AWS] Deleting ELBs"
    all_elbs=$(aws elbv2 describe-load-balancers \
            --query 'LoadBalancers[*].{ARN:LoadBalancerArn,VPCID:VpcId}' \
            --region "${AWS_REGION}" \
            --output text \
            | grep "${VPC_ID}" \
            | xargs -n1 | sed -n 'p;n')

    for elb in ${all_elbs}; do
        listeners=$(aws elbv2 describe-listeners \
            --load-balancer-arn "${elb}" \
            --query 'Listeners[].{ARN:ListenerArn}' \
            --region "${AWS_REGION}" \
            --output text)

        for lis in ${listeners}; do
            echo "      - Deleting listener '${lis}'"
            aws elbv2 delete-listener \
                --listener-arn "${lis}" \
                --region "${AWS_REGION}" \
                --output text
        done

        echo "      - Deleting ELB '${elb}'"
        aws elbv2 delete-load-balancer \
            --load-balancer-arn "${elb}" \
            --region "${AWS_REGION}" \
            --output text
    done

    echo_heading "[AWS] Deleting ASGs"
    for asg in $(aws autoscaling describe-auto-scaling-groups \
        --query AutoScalingGroups[].AutoScalingGroupName \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Deleting ASG '${asg}'"
        aws autoscaling delete-auto-scaling-group \
            --auto-scaling-group-name ${asg} \
            --force-delete \
            --region ${AWS_REGION}
    done

    echo "      - Waiting for instances to terminate"
    for instance in $(aws ec2 describe-instances \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text \
        --region "${AWS_REGION}")
    do
        aws ec2 terminate-instances \
            --instance-ids "${instance}" \
            --region "${AWS_REGION}" > /dev/null

        aws ec2 wait instance-terminated \
            --instance-ids "${instance}" \
            --region "${AWS_REGION}"
    done

    echo_heading "[AWS] Deleting NAT Gateways"
    for ngw in $(aws ec2 describe-nat-gateways \
        --filter 'Name=vpc-id,Values='${VPC_ID} \
                'Name=state,Values=available' \
        --query 'NatGateways[].NatGatewayId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Deleting NAT Gateway '${ngw}'"
        aws ec2 delete-nat-gateway \
            --nat-gateway-id "${ngw}" \
            --region "${AWS_REGION}" > /dev/null
    done

    echo "      - Waiting for NAT Gateways to be deleted"
    while :
    do
        state=$(aws ec2 describe-nat-gateways \
            --filter 'Name=vpc-id,Values='${VPC_ID} \
                    'Name=state,Values=pending,available,deleting' \
            --query 'NatGateways[].State' \
            --region "${AWS_REGION}" \
            --output text)
        if [ -z "${state}" ]; then
            break
        fi
        sleep 2
    done

    echo_heading "[AWS] Deleting Elastic IPs"
    for association_id in $(aws ec2 describe-network-interfaces \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'NetworkInterfaces[].Association[].AssociationId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Disassociate EIP '${association_id}'"
        aws ec2 disassociate-address \
            --association-id ${association_id} \
            --region "${AWS_REGION}" > /dev/null
    done

    for allocation_id in $(aws ec2 describe-addresses \
        --query 'Addresses[].AllocationId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Release EIP '${allocation_id}'"
        aws ec2 release-address \
            --allocation-id ${allocation_id} \
            --region "${AWS_REGION}"
    done

    echo_heading "[AWS] Deleting Network Interface"
    for nic in $(aws ec2 describe-network-interfaces \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'NetworkInterfaces[].NetworkInterfaceId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Detach Network Interface '$nic'"
        attachment=$(aws ec2 describe-network-interfaces \
            --filters 'Name=vpc-id,Values='${VPC_ID} \
                    'Name=network-interface-id,Values='${nic} \
            --query 'NetworkInterfaces[].Attachment.AttachmentId' \
            --region "${AWS_REGION}" \
            --output text)

        if [ ! -z ${attachment} ]; then
            aws ec2 detach-network-interface \
                --attachment-id "${attachment}" \
                --region "${AWS_REGION}" >/dev/null
            sleep 2
        fi

        echo "      - Deleting Network Interface '${nic}'"
        aws ec2 delete-network-interface \
            --network-interface-id "${nic}" \
            --region "${AWS_REGION}" > /dev/null
    done

    echo_heading "[AWS] Deleting Security Groups"
    for sg in $(aws ec2 describe-security-groups \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'SecurityGroups[].GroupId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        sg_name=$(aws ec2 describe-security-groups \
            --group-ids "${sg}" \
            --query 'SecurityGroups[].GroupName' \
            --region "${AWS_REGION}" \
            --output text)

        if [ "$sg_name" = 'default' ] || [ "$sg_name" = 'Default' ]; then
            continue
        fi

        echo "      - Deleting Security group '${sg}'"
        ip_permissions=$(aws ec2 describe-security-groups --region ${AWS_REGION} --group-ids ${sg} --query "SecurityGroups[0].IpPermissions" --output json)
        if [[ ${ip_permissions} != "[]" ]]; then
            aws ec2 revoke-security-group-ingress \
                --group-id ${sg} \
                --region "${AWS_REGION}" \
                --ip-permissions "${ip_permissions}" &>/dev/null
            sleep 1
        fi

        aws ec2 delete-security-group \
            --group-id "${sg}" \
            --region "${AWS_REGION}" &>/dev/null
    done

    for sg in $(aws ec2 describe-security-groups \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'SecurityGroups[].GroupId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        sg_name=$(aws ec2 describe-security-groups \
            --group-ids "${sg}" \
            --query 'SecurityGroups[].GroupName' \
            --region "${AWS_REGION}" \
            --output text)

        if [ "$sg_name" = 'default' ] || [ "$sg_name" = 'Default' ]; then
            continue
        fi

        aws ec2 delete-security-group \
            --group-id "${sg}" \
            --region "${AWS_REGION}" >/dev/null
    done

    echo_heading "[AWS] Deleting Internet Gateway"
    for igw in $(aws ec2 describe-internet-gateways \
        --filters 'Name=attachment.vpc-id,Values='${VPC_ID} \
        --query 'InternetGateways[].InternetGatewayId' \
        --region "${AWS_REGION}" \
        --output text)
    do
        echo "      - Detach IGW '${igw}'"
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "${igw}" \
            --vpc-id "${VPC_ID}" \
            --region "${AWS_REGION}" > /dev/null
        sleep 1

        echo "      - Deleting IGW '${igw}'"
        aws ec2 delete-internet-gateway \
            --internet-gateway-id "${igw}" \
            --region "${AWS_REGION}" > /dev/null
    done

    echo_heading "[AWS] Deleting Subnets"
    for subnet_id in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="${VPC_ID}" --region ${AWS_REGION} --query Subnets[].SubnetId --output text) ; do
        echo "      - Deleting subnet '${subnet_id}'"
        aws ec2 delete-subnet --subnet-id ${subnet_id} --region ${AWS_REGION}
    done 

    echo_heading "[AWS] Deleting Route Tables"
    for rt in $(aws ec2 describe-route-tables \
        --filters 'Name=vpc-id,Values='${VPC_ID} \
        --query 'RouteTables[].RouteTableId' \
        --output text --region "${AWS_REGION}")
    do
        main_table=$(aws ec2 describe-route-tables \
            --route-table-ids "${rt}" \
            --query 'RouteTables[].Associations[].Main' \
            --region "${AWS_REGION}" \
            --output text)

        if [ "$main_table" = 'True' ] || [ "$main_table" = 'true' ]; then
            continue
        fi

        echo "      - Deleting route table '${rt}'"
        aws ec2 delete-route-table \
            --route-table-id "${rt}" \
            --region "${AWS_REGION}" > /dev/null
    done

    echo_heading "[AWS] Deleting VPC"
    echo "      - Deleting VPC '${VPC_ID}'"
    aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${AWS_REGION}
fi

# Remove kubeconfig files
echo_heading "[Google] Deleting kubeconfig files"
gsutil -m rm -r gs://${GOOGLE_PROJECT}/kubeconfig/${EKS_PROD_1}-ksa-token.txt 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/kubeconfig/${EKS_PROD_2}-ksa-token.txt 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/kubeconfig/kubeconfig_${EKS_PROD_1} 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/kubeconfig/kubeconfig_${EKS_PROD_2} 2>/dev/null

# Remove Terraform state files
echo_heading "[Google] Deleting Terraform state files"
gsutil -m rm -r gs://${GOOGLE_PROJECT}/tfstate/prod/aws/eks 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/tfstate/prod/aws/vpc 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/tfstate/prod/gcp/asm 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/tfstate/prod/gcp/gke 2>/dev/null
gsutil -m rm -r gs://${GOOGLE_PROJECT}/tfstate/prod/gcp/vpc 2>/dev/null
