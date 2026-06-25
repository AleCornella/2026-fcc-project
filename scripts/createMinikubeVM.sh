#!/bin/bash


EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
if [[ -n "$EXISTING_TEMPLATE_ID" ]]; then
    TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
else
    bash scripts/createGoldenImageMiniKube.sh
    EXISTING_TEMPLATE_ID=$(onetemplate list -f NAME="Minikube_VM" -l ID --csv  | tail -n +2)
    TEMPLATE_ID="$EXISTING_TEMPLATE_ID"
fi

OUTPUT=$(onetemplate instantiate "$TEMPLATE_ID")
RUNNING_VM_ID=$(echo "$OUTPUT" | awk '{print $3}')