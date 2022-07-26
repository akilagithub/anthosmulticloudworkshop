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

module "dev-asm" {
  source         = "../../../../platform_admins/shared_terraform_modules/gcp/asm-gke/"
  project_id     = data.terraform_remote_state.dev_gcp_vpc.outputs.project_id
  clusters       = data.terraform_remote_state.dev_gcp_gke.outputs.clusters
  asm_properties = var.asm_properties
}
