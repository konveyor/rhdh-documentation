# Backstage RHDH Plugin Configuration Guide

This comprehensive guide outlines the steps to configure, deploy, and troubleshoot the MTA plugin for Red Hat Developer Hub (RHDH).

## Table of Contents

1. [Cluster Access](#1-get-access-to-your-cluster)
2. [MTA/Tackle Setup](#2-mta--tackle-setup-process)
3. [RHDH Operator Deployment](#3-deploy-rhdh-operator)
4. [Configmaps and Secrets](#4-configmaps-and-secrets)
5. [Keycloak Client Setup](#5-keycloak-client-setup)
6. [Plugin Deployment](#6-plugin-deployment)
   - [General Deployment](#general-deployment)
   - [Personal Registry Deployment](#personal-registry-deployment)
7. [Troubleshooting](#7-troubleshooting)

## 1. Get Access to Your Cluster

The first step is to **log in to your cluster**.

* Run the following command:

```bash
oc login --token=<your-token> --server=<your-server-url>
```

## 2. MTA / Tackle Setup Process

You need an MTA instance running in your cluster. For upstream MTA (Tackle), follow these instructions:

* **Create a Tackle instance** in the cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/konveyor/tackle2-operator/main/tackle-k8s.yaml
```

* *Note: This may take a moment for the operator to spin up*.  
* Once the Tackle instance is running, **create a Tackle Custom Resource (CR) to configure it**:

```bash
cat << EOF | kubectl apply -f -
kind: Tackle
apiVersion: tackle.konveyor.io/v1alpha1
metadata:
  name: tackle
  namespace: konveyor-tackle
spec:
  feature_auth_required: true
EOF
```

* *Alternatively, you can use the downstream MTA, with versions up to 7.2.2 supported. Version 7.3 requires an update for RHBK*.

### MTA Plugin Configuration

* **Configure the MTA plugin URL**: You will need the URL for the Tackle instance. This URL must be added to the `app-config` configmap (e.g., `app-config-rhdh.example.yaml`) under the `mta` key. **Be sure to include the `http://` or `https://` prefix**.  
* The `app-config` configmap also contains the `mta` key, which holds configurations for MTA resources, including:
  * `url`: The URL of the MTA instance
  * `backendPluginRoot`: Root URL for the MTA backend plugin
  * `version`: Version of the backend plugin

## 3. Deploy RHDH Operator

You can deploy the RHDH operator either via CLI or the operator catalog:

### CLI Method

* **Clone the RHDH operator repository** from `https://github.com/redhat-developer/rhdh-operator`.  
* **Follow the instructions in the `README.md` file**.  
* From the project root, **run `make deploy`** after cloning the repo. This ensures all Custom Resource Definitions (CRDs) are installed first.  
* **Create the Backstage RHDH CR** (Custom Resource). An example can be found at `./backstage-operator-cr.yaml`.  
  * *Note the referenced configmaps in the CR, as they are essential for the plugins to function correctly*.

### Operator Catalog Method

Simply use the OpenShift catalog to create the operator and pick the desired version.

## 4. Configmaps and Secrets

Two primary configmaps are required for the MTA plugin to load as a dynamic plugin within RHDH:

### App Config (`app-config-rhdh.example.yaml`)

* **Rename this file to `app-config-rhdh.yaml`** and update the values as needed.  
* This configmap contains the configuration for the Backstage instance.  
* **Key components** within this configmap include:  
  * `mta`: Contains configuration for MTA resources, including `url`, `backendPluginRoot`, `version`, and `providerAuth` (Keycloak authentication with `realm`, `clientId`, and `secret`).  
  * `dynamicPlugins`: Contains configuration for frontend dynamic plugins.

### Dynamic Plugins (`dynamic-plugins.yaml`)

* This configmap defines individual dynamic plugins with keys such as:
  * `package`: The package name
  * `integrity`: The integrity hash
  * `disabled`: Whether the plugin is enabled
* A script, `01-stage-dynamic-plugins.sh`, is available as a reference to package plugins into the deploy directory and generate integrity hashes.  
* When deploying plugins, you also need to **create a plugin-registry** using the `02-create-plugin-registry.sh` script.

## 5. Keycloak Client Setup

### Authentication Requirements

The MTA plugin requires proper authentication to access the MTA API. If authentication is not set up correctly, you may experience 401 errors that can cause navigation issues in the UI.

### Required Scopes

The MTA plugin requires a comprehensive set of scopes to function properly. The key scopes needed include:

#### Application Management Scopes
- `applications:get` - For reading application data
- `applications:post` - For creating applications
- `applications:put` - For updating applications
- `applications:delete` - For deleting applications

#### Analysis Scopes
- `analyses:get` - For retrieving analysis data
- `analyses:post` - For creating analyses
- `analyses:put` - For updating analyses
- `analyses:delete` - For deleting analyses
- `applications.analyses:get` - For retrieving application-specific analyses
- `applications.analyses:post` - For creating application-specific analyses

#### Task Management Scopes
- `tasks:get` - For retrieving tasks
- `tasks:post` - For creating tasks
- `tasks:put` - For updating tasks
- `tasks:delete` - For deleting tasks

#### Identity Management Scopes
- `identities:get` - For retrieving credentials
- `identities:post` - For creating credentials
- `identities:put` - For updating credentials
- `identities:delete` - For deleting credentials

#### Target Management Scopes
- `targets:get` - For retrieving targets
- `targets:post` - For creating targets
- `targets:put` - For updating targets
- `targets:delete` - For deleting targets

The full list of scopes used by the MTA plugin is extensive. The `mta-create-keycloak-client.sh` script configures all necessary scopes automatically.

### Client Setup Steps

1. Log in to your Keycloak admin console
2. Navigate to the realm that contains your MTA client
3. Select "Clients" from the left menu
4. Find your MTA client or create a new one
5. Configure the following settings:

#### Basic Settings
- **Client ID**: Your client ID (e.g., `mta-client`)
- **Enabled**: `ON`
- **Client Protocol**: `openid-connect`
- **Access Type**: `confidential`
- **Standard Flow Enabled**: `ON`
- **Direct Access Grants Enabled**: `ON`
- **Service Accounts Enabled**: `ON` (if you need service account access)

#### Advanced Settings
- **Valid Redirect URIs**: Add your Backstage URL (e.g., `https://backstage.example.com/*`)
- **Web Origins**: Add your Backstage URL or use `+` for all origins

### Client Scopes

1. Navigate to the "Client Scopes" tab
2. Add the required scopes (e.g., `applications:get`, `analyses:post`, `tasks:get`, `identities:get`, etc.)
3. Ensure these scopes are assigned to your client

### Service Account Roles (if using service accounts)

1. Navigate to the "Service Account Roles" tab
2. Assign the appropriate roles that map to the required scopes

### Automated Setup Script

We strongly recommend using the provided script to create a properly configured Keycloak client:

```bash
./mta-create-keycloak-client.sh
```

This script will:
1. Create a new client with the required settings
2. Configure all the necessary scopes (over 100 specific scopes)
3. Set up the necessary roles (tackle-admin and default-roles-mta)
4. Output the client credentials for use in your Backstage configuration

The script creates a client with ID `backstage-provider` and assigns it the appropriate service account roles and scopes.

### Backstage Configuration for Keycloak

Ensure your Backstage configuration includes the proper OAuth settings for the MTA plugin:

```yaml
auth:
  environment: development
  providers:
    keycloak:
      development:
        clientId: ${AUTH_KEYCLOAK_CLIENT_ID}
        clientSecret: ${AUTH_KEYCLOAK_CLIENT_SECRET}
        realm: ${AUTH_KEYCLOAK_REALM}
        baseUrl: ${AUTH_KEYCLOAK_BASE_URL}
```

The `providerAuth` key within `mta` in the `app-config` configmap should contain:

```yaml
providerAuth:
  realm: mta
  secret: backstage-provider-secret
  clientID: backstage-provider
```

*Note: Realm configurations may vary between upstream and downstream environments. You can verify the fields directly within the Keycloak UI. The client ID and secret names are pre-configured by the script used to create the respective Keycloak and OpenShift resources.*

## 6. Plugin Deployment

### General Deployment

#### 1. Build the Plugin

First, build the plugin using the Backstage CLI:

```bash
# From the root of the project
yarn workspace @ianbolton/backstage-plugin-mta-frontend build
```

#### 2. Export as a Dynamic Plugin

Use the Janus IDP CLI to export the plugin as a dynamic plugin:

```bash
# Navigate to the plugin directory
cd plugins/mta-frontend

# Export the plugin with the Janus IDP CLI
npx -y @janus-idp/cli@^1.11.1 package export-dynamic-plugin --clean --in-place

# Return to the project root
cd ../..
```

This will create the necessary Scalprum assets in the `dist-scalprum` directory.

#### 3. Package the Plugin

Create a tarball of the plugin for deployment:

```bash
# Create a deploy directory if it doesn't exist
mkdir -p ./deploy

# Package the plugin and capture the integrity hash
INTEGRITY_HASH=$(npm pack plugins/mta-frontend/dist-dynamic --pack-destination ./deploy --json | jq -r '.[0].integrity')

# Display the integrity hash for reference
echo "Plugin integrity hash: $INTEGRITY_HASH"
```

#### 4. Create a Plugin Registry

If you don't already have a plugin registry, you can create one using a simple HTTP server:

```bash
# Create a plugin registry using httpd
oc new-build httpd --name=plugin-registry --binary

# Start a build from the contents of the deploy directory
oc start-build plugin-registry --from-dir=./deploy --wait

# Create the plugin registry httpd instance
oc new-app --image-stream=plugin-registry
```

#### 5. Configure Dynamic Plugins

Create or update your dynamic plugins configuration:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: dynamic-plugins-config
  labels:
    app: backstage
data:
  dynamic-plugins.yaml: |
    includes:
      - dynamic-plugins.default.yaml
    plugins:
      - package: 'http://plugin-registry:8080/ianbolton-backstage-plugin-mta-frontend-0.2.0.tgz'
        disabled: false
        integrity: 'INTEGRITY_HASH_FROM_STEP_3'
```

Replace `INTEGRITY_HASH_FROM_STEP_3` with the actual integrity hash from the packaging step.

#### 6. Apply the Configuration

Apply the configuration to your cluster:

```bash
# Apply the dynamic plugins config
oc apply -f dynamic-plugins-config.yaml

# Apply any other necessary configurations
oc apply -f app-config.yaml
```

#### 7. Automated Build Script

Alternatively, you can use the `./rebuild-script.sh` command in the plugin directory. This script:

* Deletes the existing namespace for the plugin if it exists
* Runs `yarn && yarn run tsc && yarn run build:all` to compile the plugin
* Exports each plugin as a dynamic plugin to its respective `dist-dynamic` directory
* Runs `npm pack` to create a tarball of each plugin into the dynamic plugin root directory
* Creates a new namespace for the Backstage instance
* Generates the integrity hash for each plugin
* Creates the plugin registry for the dynamic plugins
* Applies the `app-config` and `dynamic-plugins` configmaps to the cluster
* Creates the Backstage instance using the RHDH operator

### Personal Registry Deployment

If you want to deploy the plugin to your own npm registry for testing, follow these steps:

#### 1. Update Plugin Version

First, update the version in your `package.json` file:

```bash
# Navigate to the plugin directory
cd plugins/mta-frontend

# Edit package.json to increment the version number
# For example, change "version": "0.1.18" to "version": "0.1.19"
```

#### 2. Build the Plugin

Build the plugin using the Backstage CLI:

```bash
# Build the plugin
npm run build
```

#### 3. Export as a Dynamic Plugin

Use the Janus IDP CLI to export the plugin as a dynamic plugin with Scalprum assets:

```bash
# Export the plugin with the Janus IDP CLI
npx -y @janus-idp/cli@^1.11.1 package export-dynamic-plugin --clean --in-place
```

This command:
- Creates the necessary Scalprum assets in the `dist-scalprum` directory
- Updates the plugin manifest
- Prepares the plugin for dynamic loading

#### 4. Publish to npm Registry

Publish the plugin to your npm registry:

```bash
# Publish the plugin
npm publish --access public
```

#### 5. Get the Integrity Hash

After publishing, retrieve the integrity hash for the plugin:

```bash
# View the plugin details and get the integrity hash
npm view @ianbolton/backstage-plugin-mta-frontend@0.1.19 dist.integrity
```

The output will look something like:
```
sha512-of7IEddPxw6I1EuB6y6ujNu6515xtwNeACjJHH5VvQ2W3tEwIPa5l7e1vklJbUZh6iJIZHMInnF1GSP7LDZ5RA==
```

#### 6. Update Dynamic Plugins Configuration

Update the dynamic plugins ConfigMap in your OpenShift cluster:

```bash
# Edit the ConfigMap
oc edit configmap backstage-dynamic-plugins
```

Add or update your plugin entry in the ConfigMap:

```yaml
## ---  MTA ---
- disabled: false
  package: '@backstage-community/backstage-plugin-mta-backend@0.4.0'
  integrity: sha512-d0Z1H9yfJBd6Z+3AIgnFPbxWBArkVBzX94L9s0zaO7n8oX3DH2itB7TZLRHXzQ4+6bhq0K2JsRbMGBbJ6KskTw==
- disabled: false
  package: '@ianbolton/backstage-plugin-mta-frontend@0.1.19'
  integrity: sha512-YOUR_NEW_INTEGRITY_HASH_HERE==
- disabled: false
  package: '@backstage-community/backstage-plugin-catalog-backend-module-mta-entity-provider@0.2.0'
  integrity: sha512-M2s8SN3/tgav+1q1RWVgxAA0V/bRFeT4GesMMWh7/WpFcrqAe65fUJ1YrTPeDavtjW27YE/RZCjwdM9xtPoc5w==
- disabled: false
  package: '@backstage-community/backstage-plugin-scaffolder-backend-module-mta@0.3.0'
  integrity: sha512-dGdjnBGmmMtvQ46LF1QUzlu+C1fnLyI0iljTJfwToOiZOxfb1vl/1gsPfT74kLSit1fYLPm8N+weS0i5+NqS8A==
```

Replace `YOUR_NEW_INTEGRITY_HASH_HERE` with the integrity hash you obtained in step 5.

#### 7. Verify Pod Restart

After updating the ConfigMap, the Backstage pods should restart automatically. Verify this with:

```bash
# Get the pods
oc get pods
```

You should see new pods being created and old ones terminating.

#### 8. Check Plugin Installation Logs

Check the logs to ensure your plugin is being installed correctly:

```bash
# Get the latest pod name
POD_NAME=$(oc get pods -l app=backstage-developer-hub -o jsonpath='{.items[0].metadata.name}')

# Check the install-dynamic-plugins container logs
oc logs $POD_NAME -c install-dynamic-plugins

# Check the main container logs
oc logs $POD_NAME
```

## 7. Troubleshooting

### Authentication Issues

If you encounter 401 errors or authentication issues:

1. Check that your Keycloak client has the correct scopes (applications:get, analyses:post, tasks:get, etc.)
2. Verify that the client credentials in your Backstage configuration are correct
3. Ensure the user has the appropriate roles assigned
4. Check the Keycloak logs for any authentication errors
5. Verify that your token includes the required scopes

#### Understanding Authentication Flow

The MTA plugin uses the following authentication flow:

1. When a user accesses the MTA plugin, it makes API requests to the MTA backend
2. If the user is not authenticated or the token is invalid, the MTA API returns a 401 error
3. The plugin displays an error message with instructions to set up the Keycloak client
4. The user can click the "Retry" button to attempt the request again

The plugin has been designed to handle authentication errors gracefully without causing page navigation issues or hard refreshes.

#### Common Authentication Issues

- **Missing Scopes**: The most common issue is missing scopes in the Keycloak client configuration. Ensure all required scopes are assigned.
- **Token Expiration**: If your token expires, you may need to refresh the page to get a new token.
- **Incorrect Client Configuration**: Verify that your client is configured correctly with the appropriate settings.
- **Network Issues**: Check that your Backstage instance can reach the Keycloak server.

### Plugin Not Loading

If the plugin is not loading:

1. Check the browser console for errors
2. Verify the integrity hash in your dynamic plugins configuration
3. Ensure the plugin registry is accessible from your Backstage instance
4. Check that the plugin URL in the dynamic plugins configuration is correct

### Navigation Issues

If you're experiencing navigation issues:

1. Check that the event handling in the plugin is correctly preventing default behavior
2. Verify that the plugin is being loaded correctly as a dynamic plugin
3. Try clearing your browser cache and reloading

### Build Issues

If you encounter build issues:

1. Make sure you're using the correct version of the Janus IDP CLI
2. Check that all dependencies are installed
3. Verify that the plugin is compatible with your version of Backstage

### Publishing Issues

If you have issues publishing:

1. Ensure you're logged in to the npm registry: `npm login`
2. Check that your package.json has the correct publishConfig settings
3. Verify that the version number has been incremented

### Scalprum Issues

If you encounter Scalprum-related issues:

1. Check that the `scalprum` section in your package.json is correctly configured:
   ```json
   "scalprum": {
     "name": "ianbolton.backstage-plugin-mta-frontend",
     "exposedModules": {
       "PluginRoot": "./src/index.ts"
     }
   }
   ```
2. Ensure the Janus IDP CLI is generating the correct Scalprum assets
3. Verify that the `dist-scalprum` directory contains the expected files

## Additional Resources

- [Janus IDP Documentation](https://github.com/janus-idp/backstage-showcase/blob/main/showcase-docs/dynamic-plugins.md)
- [Backstage Dynamic Plugins Guide](https://backstage.io/docs/plugins/dynamic-plugins)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Backstage Auth Documentation](https://backstage.io/docs/auth/)
- [npm Publishing Documentation](https://docs.npmjs.com/cli/v8/commands/npm-publish)
- [OpenShift CLI Documentation](https://docs.openshift.com/container-platform/4.12/cli_reference/openshift_cli/getting-started-cli.html)
- [Dynamic Plugins Getting Started Guide](https://github.com/gashcrumb/dynamic-plugins-getting-started/tree/main)
