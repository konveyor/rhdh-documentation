#!/bin/bash

# Variables for minikube setup
KEYCLOAK_URL="http://localhost:9001/auth"
echo "Using Keycloak URL: $KEYCLOAK_URL"

MASTER_REALM="master"
CLIENT_ID="admin-cli"
USERNAME="admin"
MTA_REALM="tackle"

# Fetch the encoded password from the secret
ENCODED_PASSWORD=$(kubectl get secret tackle-keycloak-sso -n konveyor-tackle -o jsonpath='{.data.password}')

echo "Encoded Password: $ENCODED_PASSWORD"

# Decode the password
PASSWORD=$(echo $ENCODED_PASSWORD | base64 --decode)
echo "Decoded Password: $PASSWORD"

TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/$MASTER_REALM/protocol/openid-connect/token" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  -d "grant_type=password" | jq -r '.access_token')
echo "Access Token: $TOKEN"

# Define new client JSON
NEW_CLIENT_JSON=$(cat <<'CLIENTEOF'
{
  "clientId": "backstage-provider",
  "enabled": true,
  "secret": "backstage-provider-secret",
  "redirectUris": [
    "*"
  ],
  "webOrigins": [],
  "protocol": "openid-connect",
  "attributes": {
    "access.token.lifespan": "900"
  },
  "publicClient": false,
  "bearerOnly": false,
  "consentRequired": false,
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true
}
CLIENTEOF
)

# Delete existing client if it exists
echo "Deleting existing client if it exists..."
EXISTING_CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | jq -r '.[] | select(.clientId=="backstage-provider") | .id')

if [ "$EXISTING_CLIENT_UUID" != "null" ] && [ -n "$EXISTING_CLIENT_UUID" ]; then
  echo "Found existing client with UUID: $EXISTING_CLIENT_UUID"
  DELETE_RESPONSE=$(curl -s -X DELETE "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients/$EXISTING_CLIENT_UUID" \
    -H "Authorization: Bearer $TOKEN")
  echo "Delete Response: $DELETE_RESPONSE"
fi

# Create the new client
CREATE_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$NEW_CLIENT_JSON")
echo "Create Client Response: $CREATE_RESPONSE"

# Get the client ID dynamically
CLIENT_UUID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | jq -r '.[] | select(.clientId=="backstage-provider") | .id')
echo "Client UUID: $CLIENT_UUID"

# Fetch service account user ID for the client
SERVICE_ACCOUNT_USER_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients/$CLIENT_UUID/service-account-user" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" | jq -r '.id')
echo "Service Account User ID: $SERVICE_ACCOUNT_USER_ID"

# Fetch role IDs
TACKLE_ADMIN_ROLE_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/roles/tackle-admin" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.id')
echo "Tackle Admin Role ID: $TACKLE_ADMIN_ROLE_ID"

DEFAULT_ROLES_MTA_ID=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/roles/default-roles-tackle" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.id')
echo "Default Roles MTA ID: $DEFAULT_ROLES_MTA_ID"

# Prepare role assignment JSON using the fetched IDs
ASSIGN_ROLES_PAYLOAD=$(cat <<ROLESEOF
[
  {
    "id": "$TACKLE_ADMIN_ROLE_ID",
    "name": "tackle-admin"
  },
  {
    "id": "$DEFAULT_ROLES_MTA_ID",
    "name": "default-roles-tackle"
  }
]
ROLESEOF
)
echo "Assign Roles Payload: $ASSIGN_ROLES_PAYLOAD"

# Assign roles to the service account
ASSIGN_ROLES_RESPONSE=$(curl -s -X POST "$KEYCLOAK_URL/admin/realms/$MTA_REALM/users/$SERVICE_ACCOUNT_USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$ASSIGN_ROLES_PAYLOAD")
echo "Assign Roles Response: $ASSIGN_ROLES_RESPONSE"

# Get all available client scopes and add them to the client
echo "Fetching all available client scopes..."
AVAILABLE_SCOPES=$(curl -s -X GET "$KEYCLOAK_URL/admin/realms/$MTA_REALM/client-scopes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json")

echo "Adding all available scopes to client..."
echo "$AVAILABLE_SCOPES" | jq -r '.[].id' | while read SCOPE_ID; do
  if [ -n "$SCOPE_ID" ]; then
    SCOPE_NAME=$(echo "$AVAILABLE_SCOPES" | jq -r ".[] | select(.id==\"$SCOPE_ID\") | .name")
    echo "Adding scope '$SCOPE_NAME' (ID: $SCOPE_ID) to client..."
    curl -s -X PUT "$KEYCLOAK_URL/admin/realms/$MTA_REALM/clients/$CLIENT_UUID/default-client-scopes/$SCOPE_ID" \
      -H "Authorization: Bearer $TOKEN"
  fi
done

echo "Keycloak client 'backstage-provider' has been created successfully with tackle-admin role and all available scopes."
