#!/bin/bash

OUTPUT_FILE="oci_instances_ssh_report.csv"
echo "Compartment Name,Instance Name,Instance IP,SSH Status" > "$OUTPUT_FILE"

# Get all compartments
COMPARTMENTS=$(oci iam compartment list \
    --compartment-id-in-subtree true \
    --access-level ACCESSIBLE \
    --all | jq -r '.data[] | [.id,.name] | @tsv')

# Add root tenancy compartment
TENANCY_ID=$(oci iam region-subscription list | jq -r '.data[0]."tenancy-id"')
TENANCY_NAME=$(oci iam tenancy get --tenancy-id "$TENANCY_ID" | jq -r '.data.name')
COMPARTMENTS=$(printf "%s\t%s\n%s" "$TENANCY_ID" "$TENANCY_NAME" "$COMPARTMENTS")

while IFS=$'\t' read -r COMP_ID COMP_NAME; do
    INSTANCE_IDS=$(oci compute instance list \
        --compartment-id "$COMP_ID" \
        --all 2>/dev/null | jq -r '.data[].id')

    [ -z "$INSTANCE_IDS" ] && continue

    for INSTANCE_ID in $INSTANCE_IDS; do
        INSTANCE_JSON=$(oci compute instance get --instance-id "$INSTANCE_ID")

        INSTANCE_NAME=$(echo "$INSTANCE_JSON" | jq -r '.data."display-name"')

        SSH_KEYS=$(echo "$INSTANCE_JSON" | jq -r '.data.metadata.ssh_authorized_keys // empty')

        VNIC_ID=$(oci compute instance list-vnics \
            --instance-id "$INSTANCE_ID" | jq -r '.data[0].id')

        PRIVATE_IP=$(oci network vnic get \
            --vnic-id "$VNIC_ID" | jq -r '.data."private-ip"')

        if [ -n "$SSH_KEYS" ]; then
            SSH_STATUS="Enabled"
        else
            SSH_STATUS="Disabled"
        fi

        echo "\"$COMP_NAME\",\"$INSTANCE_NAME\",\"$PRIVATE_IP\",\"$SSH_STATUS\"" >> "$OUTPUT_FILE"
    done
done <<< "$COMPARTMENTS"

echo "CSV report generated: $OUTPUT_FILE"
