#!/bin/bash

set -e

TMP_COMPARTMENTS="/tmp/oci_compartments.json"

echo "Fetching compartments..."
oci iam compartment list \
  --all \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --query 'data[].{name:name,id:id}' \
  > "$TMP_COMPARTMENTS"

ROOT_COMPARTMENT=$(oci iam tenancy get --tenancy-id "$(oci iam region-subscription list --query 'data[0]."tenancy-id"' --raw-output 2>/dev/null || echo "")" 2>/dev/null || true)

echo "volume_compartment,instance_name,kms_key_name,kms_key_compartment,vault_name,vault_compartment"

jq -c '.[]' "$TMP_COMPARTMENTS" | while read comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    ############################################
    # BLOCK VOLUMES
    ############################################
    BLOCK_VOLUMES=$(oci bv volume list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$BLOCK_VOLUMES" | jq -c '.data[]?' | while read vol; do
        VOL_ID=$(echo "$vol" | jq -r '.id')
        KMS_KEY_ID=$(echo "$vol" | jq -r '."kms-key-id" // empty')

        INSTANCE_NAME="Not Attached"
        KEY_NAME=""
        KEY_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        ATTACHMENT=$(oci compute volume-attachment list \
            --compartment-id "$COMP_ID" \
            --all 2>/dev/null | jq -c ".data[]? | select(.\"volume-id\"==\"$VOL_ID\")" | head -1)

        if [[ -n "$ATTACHMENT" ]]; then
            INSTANCE_ID=$(echo "$ATTACHMENT" | jq -r '."instance-id"')
            INSTANCE_NAME=$(oci compute instance get \
                --instance-id "$INSTANCE_ID" \
                --query 'data."display-name"' \
                --raw-output 2>/dev/null || echo "Unknown")
        fi

        if [[ -n "$KMS_KEY_ID" ]]; then
            KEY_JSON=$(oci kms management key get \
                --key-id "$KMS_KEY_ID" 2>/dev/null || echo '{}')

            KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name" // "Unknown"')
            KEY_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id" // empty')
            VAULT_ID=$(echo "$KEY_JSON" | jq -r '.data."vault-id" // empty')

            if [[ -n "$KEY_COMP_ID" ]]; then
                KEY_COMP=$(jq -r ".[] | select(.id==\"$KEY_COMP_ID\") | .name" "$TMP_COMPARTMENTS")
            fi

            if [[ -n "$VAULT_ID" ]]; then
                VAULT_JSON=$(oci kms management vault get \
                    --vault-id "$VAULT_ID" 2>/dev/null || echo '{}')

                VAULT_NAME=$(echo "$VAULT_JSON" | jq -r '.data."display-name" // "Unknown"')
                VAULT_COMP_ID=$(echo "$VAULT_JSON" | jq -r '.data."compartment-id" // empty')

                if [[ -n "$VAULT_COMP_ID" ]]; then
                    VAULT_COMP=$(jq -r ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" "$TMP_COMPARTMENTS")
                fi
            fi
        fi

        echo "\"$COMP_NAME\",\"$INSTANCE_NAME\",\"$KEY_NAME\",\"$KEY_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done

    ############################################
    # BOOT VOLUMES
    ############################################
    BOOT_VOLUMES=$(oci bv boot-volume list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$BOOT_VOLUMES" | jq -c '.data[]?' | while read vol; do
        VOL_ID=$(echo "$vol" | jq -r '.id')
        KMS_KEY_ID=$(echo "$vol" | jq -r '."kms-key-id" // empty')
        INSTANCE_NAME="Boot Volume"

        KEY_NAME=""
        KEY_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        if [[ -n "$KMS_KEY_ID" ]]; then
            KEY_JSON=$(oci kms management key get \
                --key-id "$KMS_KEY_ID" 2>/dev/null || echo '{}')

            KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name" // "Unknown"')
            KEY_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id" // empty')
            VAULT_ID=$(echo "$KEY_JSON" | jq -r '.data."vault-id" // empty')

            if [[ -n "$KEY_COMP_ID" ]]; then
                KEY_COMP=$(jq -r ".[] | select(.id==\"$KEY_COMP_ID\") | .name" "$TMP_COMPARTMENTS")
            fi

            if [[ -n "$VAULT_ID" ]]; then
                VAULT_JSON=$(oci kms management vault get \
                    --vault-id "$VAULT_ID" 2>/dev/null || echo '{}')

                VAULT_NAME=$(echo "$VAULT_JSON" | jq -r '.data."display-name" // "Unknown"')
                VAULT_COMP_ID=$(echo "$VAULT_JSON" | jq -r '.data."compartment-id" // empty')

                if [[ -n "$VAULT_COMP_ID" ]]; then
                    VAULT_COMP=$(jq -r ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" "$TMP_COMPARTMENTS")
                fi
            fi
        fi

        echo "\"$COMP_NAME\",\"$INSTANCE_NAME\",\"$KEY_NAME\",\"$KEY_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
########
#!/bin/bash
set -euo pipefail

PROFILE="${PROFILE:-DEFAULT}"
TMP_COMPARTMENTS="/tmp/oci_compartments.json"

echo "Using OCI profile: $PROFILE" >&2
echo "Fetching compartments..." >&2

oci --profile "$PROFILE" iam compartment list \
    --all \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --query 'data[].{name:name,id:id}' \
    > "$TMP_COMPARTMENTS"

echo "volume_compartment,instance_name,kms_key_name,kms_key_compartment,vault_name,vault_compartment"

jq -c '.[]' "$TMP_COMPARTMENTS" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    BOOT_VOLUMES=$(oci --profile "$PROFILE" bv boot-volume list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$BOOT_VOLUMES" | jq -c '.data[]?' | while read -r vol; do
        BOOT_VOL_ID=$(echo "$vol" | jq -r '.id')
        KMS_KEY_ID=$(echo "$vol" | jq -r '."kms-key-id" // empty')

        INSTANCE_NAME="Not Attached"
        KEY_NAME=""
        KEY_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        ####################################
        # Find attached instance
        ####################################
        ATTACHMENT=$(oci --profile "$PROFILE" compute boot-volume-attachment list \
            --compartment-id "$COMP_ID" \
            --all 2>/dev/null \
            | jq -c ".data[]? | select(.\"boot-volume-id\"==\"$BOOT_VOL_ID\")" \
            | head -1)

        if [[ -n "$ATTACHMENT" ]]; then
            INSTANCE_ID=$(echo "$ATTACHMENT" | jq -r '."instance-id"')

            INSTANCE_NAME=$(oci --profile "$PROFILE" compute instance get \
                --instance-id "$INSTANCE_ID" \
                --query 'data."display-name"' \
                --raw-output 2>/dev/null || echo "Unknown")
        fi

        ####################################
        # KMS lookup
        ####################################
        if [[ -n "$KMS_KEY_ID" ]]; then
            KEY_JSON=$(oci --profile "$PROFILE" kms management key get \
                --key-id "$KMS_KEY_ID" 2>/dev/null || echo '{}')

            KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name" // "Unknown"')
            KEY_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id" // empty')
            VAULT_ID=$(echo "$KEY_JSON" | jq -r '.data."vault-id" // empty')

            if [[ -n "$KEY_COMP_ID" ]]; then
                KEY_COMP=$(jq -r \
                    ".[] | select(.id==\"$KEY_COMP_ID\") | .name" \
                    "$TMP_COMPARTMENTS")
            fi

            ####################################
            # Vault lookup
            ####################################
            if [[ -n "$VAULT_ID" ]]; then
                VAULT_JSON=$(oci --profile "$PROFILE" kms management vault get \
                    --vault-id "$VAULT_ID" 2>/dev/null || echo '{}')

                VAULT_NAME=$(echo "$VAULT_JSON" | jq -r '.data."display-name" // "Unknown"')
                VAULT_COMP_ID=$(echo "$VAULT_JSON" | jq -r '.data."compartment-id" // empty')

                if [[ -n "$VAULT_COMP_ID" ]]; then
                    VAULT_COMP=$(jq -r \
                        ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" \
                        "$TMP_COMPARTMENTS")
                fi
            fi
        fi

        echo "\"$COMP_NAME\",\"$INSTANCE_NAME\",\"$KEY_NAME\",\"$KEY_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
####

#!/bin/bash
set -euo pipefail

PROFILE="${PROFILE:-DEFAULT}"
TMP_COMPARTMENTS="/tmp/oci_compartments.json"

# Get all compartments
oci --profile "$PROFILE" iam compartment list \
    --all \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --query 'data[].{name:name,id:id}' \
    > "$TMP_COMPARTMENTS"

echo "compartment_name,boot_volume_name,kms_key_name,kms_compartment,vault_name,vault_compartment"

jq -c '.[]' "$TMP_COMPARTMENTS" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    BOOT_VOLUMES=$(oci --profile "$PROFILE" bv boot-volume list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$BOOT_VOLUMES" | jq -c '.data[]?' | while read -r vol; do
        BOOT_VOL_NAME=$(echo "$vol" | jq -r '."display-name"')
        KMS_KEY_ID=$(echo "$vol" | jq -r '."kms-key-id" // empty')

        KMS_KEY_NAME=""
        KMS_COMP=""
        VAULT_NAME=""
        VAULT_COMP=""

        if [[ -n "$KMS_KEY_ID" ]]; then
            KEY_JSON=$(oci --profile "$PROFILE" kms management key get \
                --key-id "$KMS_KEY_ID" 2>/dev/null || echo '{}')

            KMS_KEY_NAME=$(echo "$KEY_JSON" | jq -r '.data."display-name" // ""')
            KMS_COMP_ID=$(echo "$KEY_JSON" | jq -r '.data."compartment-id" // ""')
            VAULT_ID=$(echo "$KEY_JSON" | jq -r '.data."vault-id" // ""')

            if [[ -n "$KMS_COMP_ID" ]]; then
                KMS_COMP=$(jq -r \
                    ".[] | select(.id==\"$KMS_COMP_ID\") | .name" \
                    "$TMP_COMPARTMENTS")
            fi

            if [[ -n "$VAULT_ID" ]]; then
                VAULT_JSON=$(oci --profile "$PROFILE" kms management vault get \
                    --vault-id "$VAULT_ID" 2>/dev/null || echo '{}')

                VAULT_NAME=$(echo "$VAULT_JSON" | jq -r '.data."display-name" // ""')
                VAULT_COMP_ID=$(echo "$VAULT_JSON" | jq -r '.data."compartment-id" // ""')

                if [[ -n "$VAULT_COMP_ID" ]]; then
                    VAULT_COMP=$(jq -r \
                        ".[] | select(.id==\"$VAULT_COMP_ID\") | .name" \
                        "$TMP_COMPARTMENTS")
                fi
            fi
        fi

        echo "\"$COMP_NAME\",\"$BOOT_VOL_NAME\",\"$KMS_KEY_NAME\",\"$KMS_COMP\",\"$VAULT_NAME\",\"$VAULT_COMP\""
    done
done
