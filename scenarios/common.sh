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

# This script is intended to be sourced by the scenario scripts.
# It handles common configuration and GKE authentication.

# --- Configuration ---
# Default values
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
REGION="us-central1"
CLUSTER_NAME=""
NAMESPACE="online-boutique-demo"

# Function to display help for common options
show_common_help() {
  echo "Common Options:"
  echo "  --project=ID       GCP Project ID (default: active gcloud project)"
  echo "  --region=NAME      GCP Region (default: us-central1)"
  echo "  --cluster=NAME     GKE Cluster Name (default: online-boutique-<hash>)"
  echo "  --namespace=NAME   K8s Namespace (default: demo)"
}

# Parse common arguments
# Note: We use a copy of arguments to avoid consuming positional arguments of the calling script.
TEMP_ARGS=()
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
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    *)
      TEMP_ARGS+=("$1")
      shift
      ;;
  esac
done

# Restore non-common arguments to $@
set -- ${TEMP_ARGS[@]+"${TEMP_ARGS[@]}"}

# Calculate unique cluster name based on project ID hash if not explicitly set
if [[ -z "$CLUSTER_NAME" ]] && [[ -n "$PROJECT_ID" ]]; then
  PROJECT_HASH=$(echo -n "$PROJECT_ID" | md5sum 2>/dev/null | cut -c1-6 || echo -n "$PROJECT_ID" | md5 2>/dev/null | cut -c1-6 || echo "demo")
  CLUSTER_NAME="online-boutique-${PROJECT_HASH}"
fi

# Validation
if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ Error: PROJECT_ID is not set. Use --project flag or 'gcloud config set project <PROJECT_ID>'"
  exit 1
fi

# Authenticate with GKE
echo "🔐 Authenticating with GKE cluster: $CLUSTER_NAME..."
if ! gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" > /dev/null 2>&1; then
  echo "❌ Error: Failed to authenticate with GKE cluster."
  exit 1
fi

# Export variables for use in calling scripts
export PROJECT_ID
export REGION
export CLUSTER_NAME
export NAMESPACE
