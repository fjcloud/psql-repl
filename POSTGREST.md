# PostgREST Integration

This document describes how to set up PostgREST with the PostgreSQL replication configuration.

## Kubernetes OAuth Integration

PostgREST can be configured to work with Kubernetes OAuth for authentication and authorization. This setup allows using Kubernetes service accounts to control access to the PostgreSQL database through PostgREST.

### 1. Database Role Setup

First, create a PostgreSQL role that matches your service account's full name from the `sub` claim:

```bash
# Connect to primary and create the database role
oc rsh deployment/postgres-primary psql -U postgres -d mydatabase -c "
CREATE ROLE \"system:serviceaccount:psql-repl:dbreader\" NOLOGIN;
GRANT SELECT ON TABLE sample_table TO \"system:serviceaccount:psql-repl:dbreader\";
GRANT \"system:serviceaccount:psql-repl:dbreader\" TO myuser;
"
```

This creates a role matching the full service account name from the JWT's `sub` claim.

### 2. Service Account Creation

Create a Kubernetes service account that will be used for authentication:

```bash
oc create sa dbreader
```

### 3. PostgREST Deployment

Deploy PostgREST with Kubernetes OAuth configuration:

```bash
oc new-app docker.io/postgrest/postgrest \
  --name=postgrest \
  -e PGRST_DB_URI="postgres://myuser:mypassword@postgres-replica,postgres-primary/mydatabase?target_session_attrs=read-only" \
  -e PGRST_DB_SCHEMA="public" \
  -e PGRST_SERVER_HOST="0.0.0.0" \
  -e PGRST_SERVER_PORT="3000" \
  -e PGRST_JWT_SECRET="$(oc get --raw /openid/v1/jwks)" \
  -e PGRST_JWT_ROLE_CLAIM_KEY=".sub" \
  -e PGRST_DB_POOL="10" \
  -e PGRST_DB_POOL_TIMEOUT="10" \
  -e PGRST_DB_MAX_ROWS="1000" \
  -e PGRST_LOG_LEVEL="debug"
```

Key configuration parameters:
- `PGRST_JWT_SECRET`: Uses Kubernetes JWKS endpoint for JWT validation
- `PGRST_JWT_ROLE_CLAIM_KEY`: Maps the JWT's `sub` claim (full service account name) to PostgreSQL role
- `PGRST_DB_URI`: Configures connection to both primary and replica with read-only preference

### 4. Create Route

Expose PostgREST through an OpenShift route:

```bash
oc create route edge postgrest --service=postgrest
```

### 5. Testing the Setup

Test the API using a service account token:

```bash
# Get the route hostname
POSTGREST_HOST=$(oc get route postgrest -o jsonpath='{.spec.host}')

# Test with service account token
curl -k "https://${POSTGREST_HOST}/sample_table" \
  -H "Authorization: Bearer $(oc create token dbreader)"
```

### How it Works

1. The client requests a token for the service account (`dbreader`)
2. The token contains:
   - Full service account name in `sub` claim as `system:serviceaccount:psql-repl:dbreader`
   - Standard Kubernetes claims for authentication
3. PostgREST validates:
   - Token signature using Kubernetes JWKS
4. PostgREST extracts the full service account name from the `sub` claim
5. PostgREST connects to PostgreSQL using the matching role name
6. PostgreSQL permissions are enforced based on the role grants

This setup provides secure, OAuth-based authentication while maintaining PostgreSQL's role-based access control.

## References

- [PostgREST Documentation](https://postgrest.org/)
- [PostgreSQL Connection URIs](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING) 
