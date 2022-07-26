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

locals {
  header                = <<EOT
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: asm-multicloud
  revision: ASM_REV_LABEL
EOT
  header_empty                = <<EOT
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: ingress
spec:
  profile: empty
  revision: ASM_REV_LABEL
EOT
  gateway_component         = <<EOT
  components:
    ingressGateways:
    - name: istio-ingressgateway
      enabled: false
EOT
  eks_component         = <<EOT
  components:
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        service_annotations:
          service.beta.kubernetes.io/aws-load-balancer-type: nlb
        env:
        - name: TRUST_DOMAIN
          value: PROJECT_ID.svc.id.goog
        - name: CA_ADDR
          value: meshca.googleapis.com:443
        - name: GKE_CLUSTER_URL
          value: https://gkehub.googleapis.com/projects/PROJECT_ID/locations/global/memberships/CLUSTER_NAME

EOT
  gke_component         = <<EOT
  components:
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        service_annotations:
          cloud.google.com/neg: '{"exposed_ports": {"80":{}}}'
          anthos.cft.dev/autoneg: '{"name":"ENV-istio-ingressgateway-backend-svc", "max_rate_per_endpoint":100}'
        env:
        - name: TRUST_DOMAIN
          value: PROJECT_ID.svc.id.goog
        - name: CA_ADDR
          value: meshca.googleapis.com:443
EOT
  gke_meshconfig        = <<EOT
  meshConfig:
    accessLogFile: "/dev/stdout"
    defaultConfig:
      proxyMetadata:
        # istiocoredns deprecation
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_PROXY_XDS_VIA_AGENT: "true"
EOT
  eks_meshconfig        = <<EOT
  meshConfig:
    accessLogFile: "/dev/stdout"
    defaultConfig:
      proxyMetadata:
        # istiocoredns deprecation
        ISTIO_META_DNS_CAPTURE: "true"
        ISTIO_META_PROXY_XDS_VIA_AGENT: "true"      
        ISTIO_METAJSON_PLATFORM_METADATA: |-
          {\"PLATFORM_METADATA\":{\"gcp_gke_cluster_name\":\"EKS\",\"gcp_project\":\"PROJECT_ID\",\"gcp_location\":\"CLUSTER_LOCATION\"}}
EOT
  gcp_values            = <<EOT
  values:
    telemetry:
      enabled: true
      v2:
        enabled: true
        prometheus:
          enabled: true        
        stackdriver:
          enabled: true  # This enables Stackdriver metrics
    global:
      podDNSSearchNamespaces:
        - global
      meshID: MESH_ID
      multiCluster:
        clusterName: cn-PROJECT_ID-global-GKE
      network: GCP_NET
      meshNetworks:
        GCP_NET:
          endpoints:
          # Always use Kubernetes as the registry name for the main cluster in the mesh network configuration
EOT
  eks_values            = <<EOT
  values:
    telemetry:
      enabled: true
      v2:
        enabled: true
        stackdriver:
          enabled: true  # This enables Stackdriver metrics       
    global:
      podDNSSearchNamespaces:
        - global
      meshID: MESH_ID
      multiCluster:
        clusterName: cn-PROJECT_ID-global-EKS
      network: EKS-net
      meshNetworks:
        GCP_NET:
          endpoints:
          # Always use Kubernetes as the registry name for the main cluster in the mesh network configuration
EOT
  gcp_registry          = <<EOT
          - fromRegistry: GKE
EOT
  gateways_registry     = <<EOT
          gateways:
          - registry_service_name: istio-eastwestgateway.istio-system.svc.cluster.local
            port: 15443
EOT
  eks_self_network      = <<EOT
        EKS-net:
          endpoints:
          - fromRegistry: EKS
          gateways:
          - registry_service_name: istio-eastwestgateway.istio-system.svc.cluster.local
            port: 15443
EOT
  eks_remote_network    = <<EOT
        EKS-net:
          endpoints:
          - fromRegistry: EKS
          gateways:
          - address: ISTIOINGRESS_IP
            port: 15443
EOT
  gke_kubedns_configmap = <<EOT
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
data:
  stubDomains: |
    {"global": ["COREDNS_IP"]}
EOT
  eks_coredns_configmap = <<EOT
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           upstream
           fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
    global:53 {
        errors
        cache 30
        forward . COREDNS_IP:53
    }
EOT
  eastwestgateway_eks = <<EOT
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  revision: ASM_REV_LABEL
  profile: empty
  components:
    ingressGateways:
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: MESH_NETWORK
        enabled: true
        k8s:
          env:
            # sni-dnat adds the clusters required for AUTO_PASSTHROUGH mode
            - name: ISTIO_META_ROUTER_MODE
              value: "sni-dnat"
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: MESH_NETWORK
            - name: CA_ADDR
              value: meshca.googleapis.com:443
            - name: TRUST_DOMAIN
              value: PROJECT_ID.svc.id.goog
            - name: GKE_CLUSTER_URL
              value: https://gkehub.googleapis.com/projects/PROJECT_ID/locations/global/memberships/CLUSTER_NAME
          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
EOT
  eastwestgateway_gke = <<EOT
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: eastwest
spec:
  revision: ASM_REV_LABEL
  profile: empty
  components:
    ingressGateways:
      - name: istio-eastwestgateway
        label:
          istio: eastwestgateway
          app: istio-eastwestgateway
          topology.istio.io/network: MESH_NETWORK
        enabled: true
        k8s:
          env:
            # sni-dnat adds the clusters required for AUTO_PASSTHROUGH mode
            - name: ISTIO_META_ROUTER_MODE
              value: "sni-dnat"
            # traffic through this gateway should be routed inside the network
            - name: ISTIO_META_REQUESTED_NETWORK_VIEW
              value: MESH_NETWORK
            - name: CA_ADDR
              value: meshca.googleapis.com:443
            - name: TRUST_DOMAIN
              value: PROJECT_ID.svc.id.goog

          service:
            ports:
              - name: status-port
                port: 15021
                targetPort: 15021
              - name: tls
                port: 15443
                targetPort: 15443
              - name: tls-istiod
                port: 15012
                targetPort: 15012
              - name: tls-webhook
                port: 15017
                targetPort: 15017
EOT
  gateway_values = <<EOT
  values:
    global:
      pilotCertProvider: kubernetes
      sds:
        token:
          aud: PROJECT_ID.svc.id.goog
      meshID: proj-PROJECT_NUMBER
      network: MESH_NETWORK
      multiCluster:
        clusterName: cn-PROJECT_ID-global-CLUSTER_NAME
EOT
}