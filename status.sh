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

# Source common configuration and authenticate
# We assume status.sh is in the root, and common.sh is in scenarios/
SCRIPT_DIR=$(dirname "$0")
source "$SCRIPT_DIR/scenarios/common.sh"

# Help message (overriding the common one to be more specific)
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./status.sh [OPTIONS]"
  echo ""
  show_common_help
  exit 0
fi

echo "--------------------------------------------------------"
echo "📊 Online Boutique Demo Status"
echo "Project: $PROJECT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "--------------------------------------------------------"

# 1. Check Cluster
if ! gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" > /dev/null 2>&1; then
  echo "❌ Cluster not found or not accessible."
  exit 1
fi

# 2. Check Outage Scenarios
echo "🕵️  Checking for Active Outage Scenarios..."
HAS_OUTAGE=false

# 2.1 Check for Latency (CPU Throttling & Artificial Latency)
CPU_LIMIT=$(kubectl get deployment productcatalogservice -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "unknown")
EXTRA_LATENCY=$(kubectl get deployment productcatalogservice -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="EXTRA_LATENCY")].value}' 2>/dev/null || echo "")

# Autopilot might adjust 10m to 100m, so we check for <= 100m
if [[ "$CPU_LIMIT" == "10m" ]] || [[ "$CPU_LIMIT" == "100m" ]] || [[ -n "$EXTRA_LATENCY" ]]; then
  echo "  ⚠️  LATENCY: productcatalogservice is degraded."
  [[ "$CPU_LIMIT" == "10m" || "$CPU_LIMIT" == "100m" ]] && echo "      - CPU is throttled ($CPU_LIMIT)"
  [[ -n "$EXTRA_LATENCY" ]] && echo "      - Artificial latency injected ($EXTRA_LATENCY)"
  HAS_OUTAGE=true
fi

# 2.2 Check for Connectivity (NetworkPolicy)
if kubectl get networkpolicy block-cart-ingress -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "  ⚠️  CONNECTIVITY: cartservice ingress is blocked by NetworkPolicy."
  HAS_OUTAGE=true
fi

# 2.3 Check for Crash (Invalid Config)
PAYMENT_PORT=$(kubectl get deployment paymentservice -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PORT")].value}' 2>/dev/null || echo "")
if [[ "$PAYMENT_PORT" == "INVALID_PORT" ]]; then
  echo "  ⚠️  RELIABILITY: paymentservice has invalid PORT configuration."
  HAS_OUTAGE=true
fi

if [[ "$HAS_OUTAGE" == "false" ]]; then
  echo "  ✅ No active outage scenarios detected."
fi
echo ""

# 2.4 Check for Load Generator Scaling
echo "📈 Checking Load Generator Status..."
LG_USERS=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="USERS")].value}' 2>/dev/null || echo "10")
LG_RATE=$(kubectl get deployment loadgenerator -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RATE")].value}' 2>/dev/null || echo "1")

if [[ "$LG_USERS" != "10" ]] || [[ "$LG_RATE" != "1" ]]; then
  echo "  ⚠️  LOAD: Load generator is Scaled UP."
  echo "      - Target Users: $LG_USERS (default: 10)"
  echo "      - Spawn Rate:   $LG_RATE (default: 1)"
else
  echo "  ✅ Load generator is running at default capacity (10 users)."
fi
echo ""

# 3. Check Pods
echo "📦 Pod Status in namespace '$NAMESPACE':"
kubectl get pods -n "$NAMESPACE"

# 3. Check Services
echo ""
echo "🌐 Service Endpoints:"
kubectl get svc -n "$NAMESPACE"

# 4. Check Frontend specifically
EXTERNAL_IP=$(kubectl get service frontend-external -n "${NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$EXTERNAL_IP" ]; then
  echo ""
  echo "🌎 Frontend is LIVE at: http://$EXTERNAL_IP"
  
  # Optional: Quick curl check
  if curl -s -I "http://$EXTERNAL_IP" | grep -q "200 OK"; then
    echo "✅ Health check: OK"
  else
    echo "⚠️  Health check: Frontend returned non-200 status or is unreachable."
  fi
else
  echo ""
  echo "⏳ Frontend External IP is still pending..."
fi
echo "--------------------------------------------------------"
