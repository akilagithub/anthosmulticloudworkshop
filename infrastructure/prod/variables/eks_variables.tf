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

variable "eks1_cluster_name" { default = "eks-prod-eu-west1ab-1" }
variable "eks2_cluster_name" { default = "eks-prod-eu-west1ab-2" }

variable "env" { default = "prod" }

variable "config-repo" { default = "config" }

###MARKER###
