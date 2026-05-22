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
SCRIPT_DIR=$(dirname "$0")
source "$SCRIPT_DIR/common.sh"

# Help message
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: ./scenarios/setup-crash-alert.sh [COMMON_FLAGS]"
  echo ""
  show_common_help
  exit 0
fi

POLICY_NAME="Payment Service Health Alert"

# Define the alert policy
# Condition 1: Container restarts (proxy for liveness failure)
# Condition 2: Node is not ready (node down/crash)
CAT_POLICY=$(cat <<EOF
{
  "displayName": "$POLICY_NAME",
  "documentation": {
    "content": "The paymentservice or its underlying node is unhealthy. This alert triggers if the container restarts (often due to liveness failures) or if a GKE node is no longer Ready.",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Container Restarts: paymentservice",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_container\" AND resource.labels.namespace_name = \"$NAMESPACE\" AND resource.labels.container_name = \"server\" AND metric.type = \"kubernetes.io/container/restart_count\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_DELTA"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    },
    {
      "displayName": "Node Not Ready",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_node\" AND metric.type = \"kubernetes.io/node/status_condition\" AND metric.labels.condition = \"Ready\" AND metric.labels.status != \"true\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true
}
EOF
)

echo "--------------------------------------------------------"
echo "🔔 Setting up Alert: $POLICY_NAME"
echo "Project:   $PROJECT_ID"
echo "Namespace: $NAMESPACE"
echo "--------------------------------------------------------"

POLICY_FILE=$(mktemp)
echo "$CAT_POLICY" > "$POLICY_FILE"

# Clean up existing policy
gcloud monitoring policies list --filter="displayName='$POLICY_NAME'" --format="value(name)" --project="$PROJECT_ID" | xargs -r gcloud monitoring policies delete --quiet --project="$PROJECT_ID" || true

if gcloud monitoring policies create --policy-from-file="$POLICY_FILE" --project="$PROJECT_ID" > /dev/null 2>&1; then
  echo "✅ Alert policy created successfully."
else
  # Debug: retry once with minimal node check if it fails
  echo "❌ Error: Failed to create complex alert policy. Creating node-only alert..."
  gcloud monitoring policies create --display-name="$POLICY_NAME (Node Only)" --condition-filter="resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/status_condition\" AND metric.labels.condition=\"Ready\" AND metric.labels.status!=\"true\"" --duration=0s --if="> 0" --trigger-count=1 --project="$PROJECT_ID"
fi

rm "$POLICY_FILE"
echo "--------------------------------------------------------"
