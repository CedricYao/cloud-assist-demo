#!/bin/bash

# Copyright 2024 Google LLC
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

set -euo pipefail

# --- Configuration ---
# Default values
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
REGION="us-central1"
CLUSTER_NAME="online-boutique-demo"
ENABLE_MEMORYSTORE="false"
DEMO_DIR="microservices-demo"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project=*)
      PROJECT_ID="${1#*=}"
      shift
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    --cluster=*)
      CLUSTER_NAME="${1#*=}"
      shift
      ;;
    --memorystore=*)
      ENABLE_MEMORYSTORE="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: ./destroy.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --project=ID       GCP Project ID (default: active gcloud project)"
      echo "  --region=NAME      GCP Region (default: us-central1)"
      echo "  --cluster=NAME     GKE Cluster Name (default: online-boutique-demo)"
      echo "  --memorystore=BOOL Use Memorystore (default: false)"
      exit 0
      ;;
    *)
      echo "❌ Error: Unknown parameter: $1"
      echo "Use --help for usage information."
      exit 1
      ;;
  esac
done

echo "--------------------------------------------------------"
echo "⚠️  WARNING: DESTRUCTIVE ACTION"
echo "This will permanently destroy the GKE cluster and all"
echo "associated resources in project: $PROJECT_ID"
echo "--------------------------------------------------------"

read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Destruction cancelled."
    exit 1
fi

echo "--------------------------------------------------------"
echo "💣 Destroying Online Boutique Demo"
echo "Project: $PROJECT_ID"
echo "--------------------------------------------------------"

if [[ ! -d "$DEMO_DIR" ]]; then
  echo "❌ Error: Directory $DEMO_DIR not found."
  exit 1
fi

pushd "$DEMO_DIR/terraform" > /dev/null

# Destroy infrastructure
terraform destroy \
  -var="gcp_project_id=${PROJECT_ID}" \
  -var="name=${CLUSTER_NAME}" \
  -var="region=${REGION}" \
  -var="memorystore=${ENABLE_MEMORYSTORE}" \
  -auto-approve

popd > /dev/null

echo "--------------------------------------------------------"
echo "✅ Destruction Complete!"
echo "--------------------------------------------------------"
