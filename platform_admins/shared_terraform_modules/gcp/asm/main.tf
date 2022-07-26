/**
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "google_project" "project" {
  project_id = var.project_id
}

resource "null_resource" "exec_create_asm_yamls" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = "${path.module}/create_asm_yamls.sh"
    environment = {
      GKE_NET                = var.gke_net
      ENV                    = var.env
      ASM_VERSION            = var.asm_version
      ASM_REV_LABEL          = var.asm_rev_label
      PROJECT_ID             = var.project_id
      PROJECT_NUMBER         = data.google_project.project.number
      GKE_LIST_STRING        = var.gke_list
      GKE_LOC_STRING         = var.gke_location_list
      EKS_LIST_STRING        = var.eks_list
      EKS_INGRESS_IPS_STRING = var.eks_ingress_ip_list
      EKS_EIP_LIST_STRING    = var.eks_eip_list
      # ASM yaml patches below
      HEADER              = local.header
      HEADER_EMPTY        = local.header_empty
      GATEWAY_COMPONENT   = local.gateway_component
      GKE_COMPONENT       = local.gke_component
      EKS_COMPONENT       = local.eks_component
      GKE_MESHCONFIG      = local.gke_meshconfig
      EKS_MESHCONFIG      = local.eks_meshconfig
      GCP_VALUES          = local.gcp_values
      EKS_VALUES          = local.eks_values
      GCP_REGISTRY        = local.gcp_registry
      GATEWAYS_REGISTRY   = local.gateways_registry
      EKS_SELF_NETWORK    = local.eks_self_network
      EKS_REMOTE_NETWORK  = local.eks_remote_network
      EASTWESTGATEWAY_EKS = local.eastwestgateway_eks
      EASTWESTGATEWAY_GKE = local.eastwestgateway_gke
      GATEWAY_VALUES      = local.gateway_values
    }
  }
  triggers = {
    build_number = "${timestamp()}"
    script_sha1  = sha1(file("${path.module}/create_asm_yamls.sh")),
  }
}

resource "null_resource" "exec_install_asm" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = "${path.module}/install_asm.sh"
    environment = {
      ASM_VERSION             = var.asm_version
      ASM_REV_LABEL           = var.asm_rev_label
      ASM_CONFIG_BRANCH       = var.asm_config_branch
      PROJECT_ID              = var.project_id
      PROJECT_NUMBER          = data.google_project.project.number
      GKE_NET                 = var.gke_net
      GKE_LIST_STRING         = var.gke_list
      GKE_LOC_STRING          = var.gke_location_list
      EKS_LIST_STRING         = var.eks_list
      EKS_EIP_LIST_STRING     = var.eks_eip_list
      GKE_KUBEDNS_CONFIGMAP   = local.gke_kubedns_configmap
      EKS_COREDNS_CONFIGMAP   = local.eks_coredns_configmap
    }
  }
  triggers = {
    //build_number = "${timestamp()}"
    script_sha1     = sha1(file("${path.module}/install_asm.sh")),
    gke_list_string = var.gke_list,
    eks_list_string = var.eks_list,
  }
  depends_on = [null_resource.exec_create_asm_yamls]
}