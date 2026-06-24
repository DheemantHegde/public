#!/bin/bash
set -euo pipefail

PROFILE="${PROFILE:-DEFAULT}"
COMP_FILE="/tmp/oci_compartments.json"

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
# CSV Header
############################################
echo "compartment_name,vcn_name,subnet_name,subnet_cidr,security_lists,route_table"

############################################
# Process compartments
############################################
jq -c '.[]' "$COMP_FILE" | while read -r comp; do
    COMP_ID=$(echo "$comp" | jq -r '.id')
    COMP_NAME=$(echo "$comp" | jq -r '.name')

    echo "Scanning compartment: $COMP_NAME" >&2

    ############################################
    # Get VCNs
    ############################################
    VCNS=$(oci --profile "$PROFILE" network vcn list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null || echo '{"data":[]}')

    echo "$VCNS" | jq -c '.data[]?' | while read -r vcn; do
        VCN_ID=$(echo "$vcn" | jq -r '.id')
        VCN_NAME=$(echo "$vcn" | jq -r '."display-name"')

        ############################################
        # Get subnets
        ############################################
        SUBNETS=$(oci --profile "$PROFILE" network subnet list \
            --compartment-id "$COMP_ID" \
            --vcn-id "$VCN_ID" \
            --all 2>/dev/null || echo '{"data":[]}')

        echo "$SUBNETS" | jq -c '.data[]?' | while read -r subnet; do
            SUBNET_NAME=$(echo "$subnet" | jq -r '."display-name"')
            SUBNET_CIDR=$(echo "$subnet" | jq -r '."cidr-block"')

            ############################################
            # Security Lists
            ############################################
            SEC_LIST_IDS=$(echo "$subnet" | jq -r '."security-list-ids"[]?')

            SEC_NAMES=""
            for SEC_ID in $SEC_LIST_IDS; do
                SEC_NAME=$(oci --profile "$PROFILE" network security-list get \
                    --security-list-id "$SEC_ID" \
                    --query 'data."display-name"' \
                    --raw-output 2>/dev/null || echo "$SEC_ID")

                if [[ -z "$SEC_NAMES" ]]; then
                    SEC_NAMES="$SEC_NAME"
                else
                    SEC_NAMES="${SEC_NAMES};${SEC_NAME}"
                fi
            done

            ############################################
            # Route Table
            ############################################
            RT_ID=$(echo "$subnet" | jq -r '."route-table-id"')

            RT_NAME=$(oci --profile "$PROFILE" network route-table get \
                --rt-id "$RT_ID" \
                --query 'data."display-name"' \
                --raw-output 2>/dev/null || echo "$RT_ID")

            ############################################
            # CSV Output
            ############################################
            echo "\"$COMP_NAME\",\"$VCN_NAME\",\"$SUBNET_NAME\",\"$SUBNET_CIDR\",\"$SEC_NAMES\",\"$RT_NAME\""
        done
    done
done
