#!/bin/bash
set -e

PROFILE="${PROFILE:-DEFAULT}"

COMP_FILE="/tmp/oci_compartments.json"
VAULT_FILE="/tmp/oci_vaults.json"

############################################
# Get all compartments
############################################
oci --profile "$PROFILE" iam compartment list \
    --all \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --query 'data[].{name:name,id:id}' \
    > "$COMP_FILE"

############################################
# Get all vaults
############################################
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
echo "secret_compartment,secret_name,kms_key_name,kms_compartment,vault_name,vault_compartment"

############################################
# Process secrets
############################################
jq -c '.[]' "$COMP_FILE" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    SECRETS=$(oci --profile "$PROFILE" vault secret list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$SECRETS" | jq -c '.data[]?' | while read -r secret; do
        SECRET_NAME=$(echo "$secret" | jq -r '."secret-name" // ."display-name" // ""')
        KEY_ID=$(echo "$secret" | jq -r '."key-id" // ."kms-key-id" // empty')
        SECRET_VAULT_ID=$(echo "$secret" | jq -r '."vault-id" // empty')

        KMS_KEY_NAME=""
        KMS_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        if [[ -n "$KEY_ID" ]]; then
            VAULT=$(jq -c \
                ".[] | select(.id==\"$SECRET_VAULT_ID\")" \
                "$VAULT_FILE")

            if [[ -n "$VAULT" ]]; then
                ENDPOINT=$(echo "$VAULT" | jq -r '."management-endpoint"')
                VAULT_NAME=$(echo "$VAULT" | jq -r '."display-name"')
                VAULT_COMP_ID=$(echo "$VAULT" | jq -r '."compartment-id"')

                VAULT_COMP=$(jq -r \
                    ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" \
                    "$COMP_FILE")

                KEY_JSON=$(oci --profile "$PROFILE" kms management key get \
                    --key-id "$KEY_ID" \
                    --endpoint "$ENDPOINT" 2>/dev/null || true)

                if [[ -n "$KEY_JSON" ]]; then
                    KMS_KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name"')
                    KMS_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id"')

                    KMS_COMP=$(jq -r \
                        ".[] | select(.id==\"$KMS_COMP_ID\") | .name" \
                        "$COMP_FILE")
                fi
            fi
        fi

        echo "\"$COMP_NAME\",\"$SECRET_NAME\",\"$KMS_KEY_NAME\",\"$KMS_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
