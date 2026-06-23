#!/bin/bash
set -euo pipefail

PROFILE="${PROFILE:-DEFAULT}"

COMP_FILE="/tmp/oci_compartments.json"
VAULT_FILE="/tmp/oci_vaults.json"

############################################
# Fetch all compartments
############################################
echo "Fetching compartments..." >&2

oci --profile "$PROFILE" iam compartment list \
    --all \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --query 'data[].{name:name,id:id}' \
    > "$COMP_FILE"

############################################
# Fetch all vaults
############################################
echo "Fetching vaults..." >&2
echo "[]" > "$VAULT_FILE"

jq -c '.[]' "$COMP_FILE" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')

    VAULTS=$(oci --profile "$PROFILE" kms management vault list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    TMP=$(mktemp)

    jq -s '.[0] + .[1].data' \
        "$VAULT_FILE" \
        <(echo "$VAULTS") > "$TMP"

    mv "$TMP" "$VAULT_FILE"
done

############################################
# CSV header
############################################
echo "cluster_compartment,cluster_name,cluster_version,kms_key_name,kms_compartment,vault_name,vault_compartment"

############################################
# Process OKE clusters
############################################
jq -c '.[]' "$COMP_FILE" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    CLUSTERS=$(oci --profile "$PROFILE" ce cluster list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$CLUSTERS" | jq -c '.data[]?' | while read -r cluster; do
        CLUSTER_ID=$(echo "$cluster" | jq -r '.id')
        CLUSTER_NAME=$(echo "$cluster" | jq -r '.name // ."display-name"')

        CLUSTER_DETAILS=$(oci --profile "$PROFILE" ce cluster get \
            --cluster-id "$CLUSTER_ID" 2>/dev/null || echo '{}')

        ############################################
        # Get cluster version
        ############################################
        CLUSTER_VERSION=$(echo "$CLUSTER_DETAILS" | jq -r '
            .data."kubernetes-version"
            // .data."kubernetesVersion"
            // "UNKNOWN"
        ')

        ############################################
        # Get KMS key ID
        ############################################
        KMS_KEY_ID=$(echo "$CLUSTER_DETAILS" | jq -r '
            .data."kms-key-id"
            // .data."kmsKeyId"
            // .data.options."kms-key-id"
            // empty
        ')

        KMS_KEY_NAME=""
        KMS_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        if [[ -n "$KMS_KEY_ID" ]]; then
            while read -r vault; do
                ENDPOINT=$(echo "$vault" | jq -r '."management-endpoint"')
                CURR_VAULT_NAME=$(echo "$vault" | jq -r '."display-name"')
                VAULT_COMP_ID=$(echo "$vault" | jq -r '."compartment-id"')

                KEY_JSON=$(oci --profile "$PROFILE" kms management key get \
                    --key-id "$KMS_KEY_ID" \
                    --endpoint "$ENDPOINT" 2>/dev/null || true)

                if [[ -n "$KEY_JSON" ]]; then
                    KMS_KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name"')
                    KMS_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id"')

                    KMS_COMP=$(jq -r \
                        ".[] | select(.id==\"$KMS_COMP_ID\") | .name" \
                        "$COMP_FILE")

                    VAULT_NAME="$CURR_VAULT_NAME"

                    VAULT_COMP=$(jq -r \
                        ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" \
                        "$COMP_FILE")

                    break
                fi
            done < <(jq -c '.[]' "$VAULT_FILE")
        fi

        echo "\"$COMP_NAME\",\"$CLUSTER_NAME\",\"$CLUSTER_VERSION\",\"$KMS_KEY_NAME\",\"$KMS_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
