# PostgreSQL Replication Makefile

# Variables
PROJECT ?= psql-repl
PRIMARY_NAME = postgres-primary
REPLICA_NAME = postgres-replica

# Database settings
DB_USER = myuser
DB_PASSWORD = mypassword
DB_NAME = mydatabase
REPL_USER = replicator
REPL_PASSWORD = replpassword
ADMIN_PASSWORD = adminpassword

# Deploy primary
deploy-primary:
	oc new-app registry.redhat.io/rhel9/postgresql-16~https://github.com/fjcloud/psql-repl.git \
		--name=$(PRIMARY_NAME) \
		-e POSTGRESQL_USER=$(DB_USER) \
		-e POSTGRESQL_PASSWORD=$(DB_PASSWORD) \
		-e POSTGRESQL_DATABASE=$(DB_NAME) \
		-e POSTGRESQL_REPLICATION_USER=$(REPL_USER) \
		-e POSTGRESQL_REPLICATION_PASSWORD=$(REPL_PASSWORD) \
		-e POSTGRESQL_REPLICA_HOST=$(REPLICA_NAME) \
		-e POSTGRESQL_ADMIN_PASSWORD=$(ADMIN_PASSWORD) \
		-e IS_PRIMARY=true
	oc set volume deployment/$(PRIMARY_NAME) --add \
		--name=postgres-data \
		--type=pvc \
		--claim-size=10Gi \
		--mount-path=/var/lib/pgsql/data

# Deploy replica
deploy-replica:
	oc new-app registry.redhat.io/rhel9/postgresql-16~https://github.com/fjcloud/psql-repl.git \
		--name=$(REPLICA_NAME) \
		-e POSTGRESQL_REPLICATION_USER=$(REPL_USER) \
		-e POSTGRESQL_REPLICATION_PASSWORD=$(REPL_PASSWORD) \
		-e POSTGRESQL_PRIMARY_HOST=$(PRIMARY_NAME) \
		-e IS_PRIMARY=false \
		-e POSTGRESQL_MIGRATION_REMOTE_HOST=$(PRIMARY_NAME) \
		-e POSTGRESQL_MIGRATION_ADMIN_PASSWORD=$(ADMIN_PASSWORD) \
		-e POSTGRESQL_MIGRATION_IGNORE_ERRORS=yes
	oc set volume deployment/$(REPLICA_NAME) --add \
		--name=postgres-data \
		--type=pvc \
		--claim-size=10Gi \
		--mount-path=/var/lib/pgsql/data

# Deploy all components
deploy-all: deploy-primary deploy-replica

# Promote replica to primary
promote-replica:
	oc exec deployment/$(REPLICA_NAME) -- pg_ctl promote -D /var/lib/pgsql/data/userdata

# Set replica to read-only
set-readonly:
	oc rsh deployment/$(REPLICA_NAME) psql -U postgres -c "ALTER SYSTEM SET default_transaction_read_only = on;"
	oc rsh deployment/$(REPLICA_NAME) psql -U postgres -c "SELECT pg_reload_conf();"

# Verify replication status
verify:
	@echo "Checking primary status..."
	@oc rsh deployment/$(PRIMARY_NAME) psql -U postgres -c "SELECT * FROM pg_stat_replication;"
	@echo "\nChecking replica status..."
	@oc rsh deployment/$(REPLICA_NAME) psql -U postgres -c "SELECT pg_is_in_recovery();"

# Create test data
create-test-data:
	oc rsh deployment/$(PRIMARY_NAME) psql -U postgres -d $(DB_NAME) -c "\
		CREATE TABLE IF NOT EXISTS sample_table ( \
			id SERIAL PRIMARY KEY, \
			data TEXT, \
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP \
		); \
		INSERT INTO sample_table (data) SELECT md5(random()::text) FROM generate_series(1, 1000);"

# Clean up primary
clean-primary:
	oc delete pvc $$(oc get deployment $(PRIMARY_NAME) -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}') --wait=false
	oc delete all -l app=$(PRIMARY_NAME)

# Clean up replica
clean-replica:
	oc delete pvc $$(oc get deployment $(REPLICA_NAME) -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}') --wait=false
	oc delete all -l app=$(REPLICA_NAME)

# Clean everything
clean-all: clean-primary clean-replica

# Show help
help:
	@echo "Available targets:"
	@echo "  deploy-primary    - Deploy primary PostgreSQL instance"
	@echo "  deploy-replica    - Deploy replica PostgreSQL instance"
	@echo "  deploy-all       - Deploy all components"
	@echo "  promote-replica   - Promote replica to primary"
	@echo "  set-readonly     - Set replica to read-only mode"
	@echo "  verify          - Check replication status"
	@echo "  create-test-data - Create test table and data"
	@echo "  clean-primary    - Remove primary instance"
	@echo "  clean-replica    - Remove replica instance"
	@echo "  clean-all       - Remove all components"

.PHONY: deploy-primary deploy-replica deploy-all promote-replica set-readonly verify create-test-data clean-primary clean-replica clean-all help 