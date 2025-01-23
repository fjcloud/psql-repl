#!/bin/bash
set -e

echo "Starting pre-start configuration..."

# Default values for unset variables
IS_PRIMARY=${IS_PRIMARY:-false}
POSTGRESQL_REPLICATION_USER=${POSTGRESQL_REPLICATION_USER:-replicator}
POSTGRESQL_PRIMARY_HOST=${POSTGRESQL_PRIMARY_HOST:-}

echo "Running as primary: ${IS_PRIMARY}"

if [ "${IS_PRIMARY}" = "false" ] && [ ! -f "${PGDATA}/standby.signal" ]; then
    echo "=== Preparing replica node ==="
    
    if [ -z "${POSTGRESQL_PRIMARY_HOST}" ]; then
        echo "ERROR: POSTGRESQL_PRIMARY_HOST is not set!"
        exit 1
    fi
    
    echo "Primary host: ${POSTGRESQL_PRIMARY_HOST}"
    echo "Replication user: ${POSTGRESQL_REPLICATION_USER}"
    
    # Create password file for pg_basebackup
    echo "Creating temporary password file..."
    export PGPASSFILE=$(mktemp)
    echo "${POSTGRESQL_PRIMARY_HOST}:5432:*:${POSTGRESQL_REPLICATION_USER}:${POSTGRESQL_REPLICATION_PASSWORD}" > "$PGPASSFILE"
    chmod 600 "$PGPASSFILE"
    
    # Stop PostgreSQL if running
    if pg_ctl status -D ${PGDATA} > /dev/null 2>&1; then
        echo "Stopping PostgreSQL server..."
        pg_ctl -D ${PGDATA} -m fast -w stop || true
        echo "PostgreSQL server stopped"
    fi
    
    # Backup existing data directory if it exists
    if [ -d "${PGDATA}" ]; then
        BACKUP_DIR="${PGDATA}.bak.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up existing data directory to ${BACKUP_DIR}..."
        mv "${PGDATA}" "${BACKUP_DIR}"
        echo "Backup completed"
    fi
    
    # Create fresh directory and perform base backup
    echo "Creating fresh PGDATA directory..."
    mkdir -p "${PGDATA}"
    
    echo "Starting base backup from primary..."
    echo "Using primary host: ${POSTGRESQL_PRIMARY_HOST}"
    echo "Using replication user: ${POSTGRESQL_REPLICATION_USER}"
    
    pg_basebackup -h ${POSTGRESQL_PRIMARY_HOST} \
                 -D ${PGDATA} \
                 -U ${POSTGRESQL_REPLICATION_USER} \
                 -P -v -R \
                 -X stream \
                 -S replica_1_slot
    
    # Clean up password file
    rm -f "$PGPASSFILE"
    
    echo "Base backup completed successfully"
    
    # Configure streaming replication
    echo "Configuring streaming replication..."
    cat >> "${PGDATA}/postgresql.auto.conf" << EOF
primary_conninfo = 'host=${POSTGRESQL_PRIMARY_HOST} port=5432 user=${POSTGRESQL_REPLICATION_USER} password=${POSTGRESQL_REPLICATION_PASSWORD} application_name=replica_1'
primary_slot_name = 'replica_1_slot'
EOF
    echo "Streaming replication configured"
    
    # Create standby signal file
    echo "Creating standby.signal file..."
    touch "${PGDATA}/standby.signal"
    
    # Set permissions
    echo "Setting directory permissions..."
    chmod 700 "${PGDATA}"
    
    echo "=== Replica preparation completed successfully ==="
else
    if [ "${IS_PRIMARY}" = "true" ]; then
        echo "Running as primary node, skipping replica preparation"
    else
        echo "Standby signal file exists, skipping replica preparation"
    fi
fi 