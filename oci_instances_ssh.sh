#!/bin/bash

OUTPUT_FILE="oci_instances_ssh_report.csv"
echo "Compartment Name,Instance Name,Instance IP,SSH Status,Operating System,OS Version,Image Name" > "$OUTPUT_FILE"

TEMP_FILE=$(mktemp)

oci iam compartment list \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --all | jq -r '.data[] | [.id,.name] | @tsv' > "$TEMP_FILE"

TENANCY_ID=$(oci iam region-subscription list | jq -r '.data[0]."tenancy-id"')
TENANCY_NAME=$(oci iam tenancy get --tenancy-id "$TENANCY_ID" | jq -r '.data.name')

echo -e "${TENANCY_ID}\t${TENANCY_NAME}" >> "$TEMP_FILE"

while IFS=$'\t' read -r COMP_ID COMP_NAME
do
    INSTANCE_IDS=$(oci compute instance list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null | jq -r '.data[].id')

    for INSTANCE_ID in $INSTANCE_IDS
    do
        INSTANCE_JSON=$(oci compute instance get --instance-id "$INSTANCE_ID")

        INSTANCE_NAME=$(echo "$INSTANCE_JSON" | jq -r '.data."display-name"')
        OS_NAME=$(echo "$INSTANCE_JSON" | jq -r '.data."operating-system" // "Unknown"')
        OS_VERSION=$(echo "$INSTANCE_JSON" | jq -r '.data."operating-system-version" // "Unknown"')
        IMAGE_ID=$(echo "$INSTANCE_JSON" | jq -r '.data."image-id" // empty')

        SSH_KEYS=$(echo "$INSTANCE_JSON" | jq -r '.data.metadata.ssh_authorized_keys // empty')

        VNIC_ID=$(oci compute instance list-vnics \
            --instance-id "$INSTANCE_ID" 2>/dev/null | jq -r '.data[0].id // empty')

        PRIVATE_IP="N/A"
        if [ -n "$VNIC_ID" ]; then
            PRIVATE_IP=$(oci network vnic get \
                --vnic-id "$VNIC_ID" 2>/dev/null | jq -r '.data."private-ip" // "N/A"')
        fi

        if [ -n "$SSH_KEYS" ]; then
            SSH_STATUS="Enabled"
        else
            SSH_STATUS="Disabled"
        fi

        IMAGE_NAME="Unknown"
        if [ -n "$IMAGE_ID" ]; then
            IMAGE_NAME=$(oci compute image get \
                --image-id "$IMAGE_ID" 2>/dev/null | jq -r '.data."display-name" // "Unknown"')
        fi

        echo "\"$COMP_NAME\",\"$INSTANCE_NAME\",\"$PRIVATE_IP\",\"$SSH_STATUS\",\"$OS_NAME\",\"$OS_VERSION\",\"$IMAGE_NAME\"" >> "$OUTPUT_FILE"
    done

done < "$TEMP_FILE"

rm -f "$TEMP_FILE"

echo "CSV generated: $OUTPUT_FILE"
