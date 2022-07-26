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

module "gke-gitlab" {
  source = "github.com/terraform-google-modules/terraform-google-gke-gitlab?ref=release-v0.5.2"

  project_id            = var.project_id
  domain                = trimprefix(module.cloud-endpoints-dns-gitlab.endpoint_computed, "gitlab.")
  certmanager_email     = "no-reply@${var.project_id}.example.com"
  gitlab_runner_install = true
  gitlab_db_name        = "gitlab-${lower(random_id.database_id.hex)}"
  gke_machine_type      = "e2-standard-4"
  # bump helm version to support tf gitlab provider 3.0+
  helm_chart_version    = "5.3.2"
  gke_version           = "1.20"
}

module "cloud-endpoints-dns-gitlab" {
  source  = "terraform-google-modules/endpoints-dns/google"
  version = "~> 2.0.1"

  project     = var.project_id
  name        = "gitlab"
  external_ip = module.gke-gitlab.gitlab_address
}

resource "random_id" "database_id" {
  byte_length = 8
}

resource "null_resource" "exec_gitlab_creds" {
  provisioner "local-exec" {
    interpreter = ["bash", "-exc"]
    command     = "${path.module}/gitlab_creds.sh"
    environment = {
      PROJECT_ID      = var.project_id
      GITLAB_HOSTNAME = module.cloud-endpoints-dns-gitlab.endpoint_computed
    }
  }
  triggers = {
    always_run = "${timestamp()}"
  }
  depends_on = [module.gke-gitlab]
}