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
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
CLUSTER_NAME="online-boutique-demo"
NAMESPACE="online-boutique-demo"
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
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    --memorystore=*)
      ENABLE_MEMORYSTORE="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: ./deploy.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --project=ID       GCP Project ID (default: active gcloud project)"
      echo "  --region=NAME      GCP Region (default: us-central1)"
      echo "  --cluster=NAME     GKE Cluster Name (default: online-boutique-demo)"
      echo "  --namespace=NAME   K8s Namespace (default: online-boutique-demo)"
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
echo "🚀 Deploying Online Boutique Demo (Service Mesh Default)"
echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo "Target:  $DEMO_DIR"
echo "--------------------------------------------------------"

# 1. Validation & Dependency Checks
if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ Error: PROJECT_ID is not set. Use --project flag or 'gcloud config set project <PROJECT_ID>'"
  exit 1
fi

check_dependency() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ Error: $1 is not installed. Please install it and try again."
    exit 1
  fi
}

check_dependency "gcloud"
check_dependency "terraform"
check_dependency "kubectl"
check_dependency "git"

# Ensure we are in the root of the repository (should contain .git)
if [[ ! -d ".git" ]]; then
  echo "❌ Error: .git directory not found. Please run this script from the root of the repository."
  exit 1
fi

# Ensure submodule is initialized
if [[ ! -d "$DEMO_DIR/terraform" ]]; then
  echo "📦 Submodule $DEMO_DIR is missing or not initialized. Attempting to initialize..."
  if git submodule update --init --recursive; then
    echo "✅ Submodule initialized successfully."
  else
    echo "❌ Error: Failed to initialize submodule. Please run 'git submodule update --init --recursive' manually."
    exit 1
  fi
fi

# 2. Enable Required APIs
# We enable these early to avoid race conditions in Terraform
echo "🔧 Enabling Required Google Cloud APIs..."
APIS=(
  "serviceusage.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "container.googleapis.com"
  "compute.googleapis.com"
  "monitoring.googleapis.com"
  "logging.googleapis.com"
  "cloudtrace.googleapis.com"
  "cloudprofiler.googleapis.com"
  "redis.googleapis.com"
  "mesh.googleapis.com"
  "anthos.googleapis.com"
  "networkmanagement.googleapis.com"
)

for api in "${APIS[@]}"; do
  echo "   - Enabling $api..."
  gcloud services enable "$api" --project="${PROJECT_ID}"
done

# 2.1 Ensure Default Network exists
# ... (rest of networking)
if ! gcloud compute networks describe default --project="${PROJECT_ID}" &>/dev/null; then
  echo "🌐 'default' VPC network not found. Creating it..."
  gcloud compute networks create default --project="${PROJECT_ID}" --subnet-mode=auto
  echo "✅ 'default' VPC network created."
fi

# 2.2 Enable Private Google Access on the default subnet (required for private GKE nodes)
echo "🔒 Enabling Private Google Access on 'default' subnet..."
gcloud compute networks subnets update default \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --enable-private-ip-google-access
echo "✅ Private Google Access enabled."

# 3. Terraform Deployment
echo "🏗️  Preparing temporary Terraform directory..."
TMP_TF_DIR="tmp-terraform"

# Preserve state if it exists to avoid losing track of the GKE cluster
STATE_BACKUP_DIR="tf-state-backup"
rm -rf "$STATE_BACKUP_DIR"
if [[ -d "$TMP_TF_DIR" ]]; then
  echo "💾 Backing up existing Terraform state..."
  mkdir -p "$STATE_BACKUP_DIR"
  [ -f "$TMP_TF_DIR/terraform.tfstate" ] && cp "$TMP_TF_DIR/terraform.tfstate" "$STATE_BACKUP_DIR/"
  [ -d "$TMP_TF_DIR/.terraform" ] && cp -r "$TMP_TF_DIR/.terraform" "$STATE_BACKUP_DIR/"
  [ -f "$TMP_TF_DIR/.terraform.lock.hcl" ] && cp "$TMP_TF_DIR/.terraform.lock.hcl" "$STATE_BACKUP_DIR/"
fi

rm -rf "$TMP_TF_DIR"
mkdir -p "$TMP_TF_DIR"
cp -r "$DEMO_DIR/terraform/"* "$TMP_TF_DIR/"

# Restore state if we backed it up
if [[ -d "$STATE_BACKUP_DIR" ]]; then
  echo "💾 Restoring Terraform state from backup..."
  [ -f "$STATE_BACKUP_DIR/terraform.tfstate" ] && cp "$STATE_BACKUP_DIR/terraform.tfstate" "$TMP_TF_DIR/"
  [ -d "$STATE_BACKUP_DIR/.terraform" ] && cp -r "$STATE_BACKUP_DIR/.terraform" "$TMP_TF_DIR/"
  [ -f "$STATE_BACKUP_DIR/.terraform.lock.hcl" ] && cp "$STATE_BACKUP_DIR/.terraform.lock.hcl" "$TMP_TF_DIR/"
  rm -rf "$STATE_BACKUP_DIR"
fi

echo "🔧 Customizing Terraform for Private GKE Cluster and Namespace..."
python3 -c '
with open("tmp-terraform/main.tf", "r") as f:
    content = f.read()

# Add private_cluster_config to GKE cluster
old_autopilot = "enable_autopilot = true"
new_autopilot = """enable_autopilot = true

  # Explicitly specify network and subnetwork (required for private Autopilot)
  network    = "default"
  subnetwork = "default"

  # Enable private nodes (required by org policy)
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }"""
content = content.replace(old_autopilot, new_autopilot)

# Set deletion_protection to false to allow future destruction
content = content.replace("# deletion_protection = false", "deletion_protection = false")

# Fix namespace creation in apply_deployment
old_apply = "kubectl apply -k ${var.filepath_manifest} -n ${var.namespace}"
new_apply = "kubectl create namespace ${var.namespace} --dry-run=client -o yaml | kubectl apply -f - && kubectl apply -k ${var.filepath_manifest} -n ${var.namespace}"
content = content.replace(old_apply, new_apply)

# Fix wait_conditions to avoid failing on missing metrics API service in Autopilot
old_wait = "kubectl wait --for=condition=AVAILABLE apiservice/v1beta1.metrics.k8s.io --timeout=180s"
new_wait = "# kubectl wait --for=condition=AVAILABLE apiservice/v1beta1.metrics.k8s.io --timeout=180s"
content = content.replace(old_wait, new_wait)

with open("tmp-terraform/main.tf", "w") as f:
    f.write(content)
'

python3 -c '
import os
if os.path.exists("tmp-terraform/memorystore.tf"):
    with open("tmp-terraform/memorystore.tf", "r") as f:
        content = f.read()
    content = content.replace("../kustomize/", "../microservices-demo/kustomize/")
    with open("tmp-terraform/memorystore.tf", "w") as f:
        f.write(content)
'

pushd "$TMP_TF_DIR" > /dev/null

terraform init

# Self-healing: If the cluster exists on GCP but is not in the Terraform state (orphaned),
# import it to avoid Error 409 (Already Exists) conflicts.
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "🌐 Cluster '${CLUSTER_NAME}' exists on GCP."
  if ! terraform state show google_container_cluster.my_cluster &>/dev/null; then
    echo "📥 Importing existing GKE cluster into Terraform state to reconcile..."
    terraform import \
      -var="gcp_project_id=${PROJECT_ID}" \
      -var="name=${CLUSTER_NAME}" \
      -var="region=${REGION}" \
      -var="namespace=${NAMESPACE}" \
      -var="memorystore=${ENABLE_MEMORYSTORE}" \
      -var="filepath_manifest=../microservices-demo/kustomize/" \
      google_container_cluster.my_cluster \
      "projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}"
  fi
fi

terraform apply \
  -var="gcp_project_id=${PROJECT_ID}" \
  -var="name=${CLUSTER_NAME}" \
  -var="region=${REGION}" \
  -var="namespace=${NAMESPACE}" \
  -var="memorystore=${ENABLE_MEMORYSTORE}" \
  -var="filepath_manifest=../microservices-demo/kustomize/" \
  -auto-approve

popd > /dev/null

# 4. Service Mesh Configuration (CSM)
echo "🕸️  Configuring Cloud Service Mesh..."

# Register the cluster to the fleet
echo "   - Registering cluster to fleet..."
gcloud container clusters update "${CLUSTER_NAME}" \
  --location "${REGION}" \
  --fleet-project "${PROJECT_ID}" \
  --project "${PROJECT_ID}"

# Enable managed mesh for the cluster
echo "   - Enabling automatic mesh management..."
gcloud container fleet mesh enable --project "${PROJECT_ID}" || true
gcloud container fleet mesh update \
  --management automatic \
  --memberships "${CLUSTER_NAME}" \
  --project "${PROJECT_ID}" \
  --location "${REGION}"

# Label the namespace for sidecar injection
echo "   - Labeling namespace '$NAMESPACE' for ASM injection..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}"
kubectl label namespace "${NAMESPACE}" istio.io/rev=asm-managed --overwrite

# Wait for managed Service Mesh control plane to be ACTIVE to prevent race conditions during pod injection
echo "   - Waiting for Cloud Service Mesh control plane to be fully active..."
MAX_MESH_RETRIES=30
MESH_RETRY=0
MESH_READY=false

while [ "$MESH_READY" = "false" ] && [ $MESH_RETRY -lt $MAX_MESH_RETRIES ]; do
  MESH_JSON=$(gcloud container fleet mesh describe --project="${PROJECT_ID}" --format=json 2>/dev/null || echo "{}")
  if echo "$MESH_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    states = data.get("membershipStates", {})
    for k, v in states.items():
        mesh = v.get("servicemesh", {})
        cp = mesh.get("controlPlaneManagement", {})
        if cp.get("state") == "ACTIVE":
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
' 2>/dev/null; then
    MESH_READY=true
    echo "     ✅ Cloud Service Mesh control plane is active."
  else
    echo "     Waiting for Service Mesh activation ($((MESH_RETRY+1))/$MAX_MESH_RETRIES)..."
    sleep 10
    ((MESH_RETRY++))
  fi
done

if [ "$MESH_READY" = "false" ]; then
  echo "     ⚠️  Warning: Service Mesh took too long to activate. Sidecar injection might be delayed."
fi

# Disable sidecar injection for loadgenerator to prevent the init container network-interception deadlock
echo "   - Disabling service mesh sidecar for loadgenerator (prevents startup deadlock)..."
kubectl patch deployment loadgenerator -n "$NAMESPACE" -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}}}'

# Restart pods to trigger injection and pick up mesh config
echo "   - Restarting pods to enable sidecar injection..."
kubectl rollout restart deployment -n "$NAMESPACE"

# 5. Success and Access Info
echo "--------------------------------------------------------"
echo "✅ Infrastructure and Application Deployed with Service Mesh"
echo ""
echo "Waiting for Frontend External IP (Istio Gateway)..."

EXTERNAL_IP=""
MAX_RETRIES=60
RETRY_COUNT=0

while [ -z "$EXTERNAL_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Check for Istio Gateway address (Gateway API)
  EXTERNAL_IP=$(kubectl get gateway istio-gateway -n "${NAMESPACE}" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
  
  # Fallback to frontend-external LoadBalancer Service if Gateway is not used
  if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$(kubectl get service frontend-external -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
  
  if [ -z "$EXTERNAL_IP" ]; then
    echo "Waiting for External IP ($((RETRY_COUNT+1))/$MAX_RETRIES)..."
    sleep 10
    ((RETRY_COUNT++))
  fi
done

if [ -n "$EXTERNAL_IP" ]; then
  echo "🌎 Frontend available at: http://$EXTERNAL_IP"
else
  echo "⚠️  Timeout waiting for External IP. Check 'kubectl get gateway -n $NAMESPACE' later."
fi
echo "--------------------------------------------------------"
