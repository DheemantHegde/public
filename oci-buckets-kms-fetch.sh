#!/bin/bash
set -e

PROFILE="${PROFILE:-DEFAULT}"

COMP_FILE="/tmp/oci_compartments.json"
VAULT_FILE="/tmp/oci_vaults.json"

############################################
# Get namespace
############################################
NAMESPACE=$(oci --profile "$PROFILE" os ns get --raw-output)

############################################
# Get compartments
############################################
echo "Fetching compartments..." >&2

oci --profile "$PROFILE" iam compartment list \
    --all \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --query 'data[].{name:name,id:id}' \
    > "$COMP_FILE"

############################################
# Get all vaults
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
# CSV Header
############################################
echo "compartment_name,bucket_name,kms_key_name,kms_compartment,vault_name,vault_compartment"

############################################
# Process buckets
############################################
jq -c '.[]' "$COMP_FILE" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    BUCKETS=$(oci --profile "$PROFILE" os bucket list \
        --compartment-id "$COMP_ID" \
        --namespace-name "$NAMESPACE" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$BUCKETS" | jq -c '.data[]?' | while read -r bucket; do
        BUCKET_NAME=$(echo "$bucket" | jq -r '.name')

        BUCKET_DETAILS=$(oci --profile "$PROFILE" os bucket get \
            --namespace-name "$NAMESPACE" \
            --bucket-name "$BUCKET_NAME" 2>/dev/null || echo '{}')

        KMS_KEY_ID=$(echo "$BUCKET_DETAILS" | jq -r '.data."kms-key-id" // empty')

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

        echo "\"$COMP_NAME\",\"$BUCKET_NAME\",\"$KMS_KEY_NAME\",\"$KMS_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
