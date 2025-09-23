---
layout: default
title: MTA Plugin Local Development
---

# MTA Plugin Local Development Guide

Simple walkthrough for setting up local development of the MTA plugin for Red Hat Developer Hub.

### Prerequisites

- Minikube
- Node.js (v18+)
- npm

### Setup Steps

#### 1. Setup MTA Backend (Tackle2-UI)

1. Clone and setup Tackle2-UI:
   ```bash
   git clone https://github.com/konveyor/tackle2-ui
   cd tackle2-ui
   ```

2. Follow the [minikube setup docs](https://github.com/konveyor/tackle2-ui/blob/main/docs/local-minikube-setup.md) to setup on minikube. 

   **Important:** Ensure `AUTH_ENABLED` is set to `true` so that the keycloak pod will be available. You will also need to set this locally wherever you run your dev server.
   
   In your Tackle CR, make sure to set:
   ```yaml
   spec:
     feature_auth_required: true
   ```

3. Start the local dev server with port forwarding:
   ```bash
   npm run start:dev
   ```
   This runs the local dev server on `http://localhost:9000`

#### 2. Setup MTA Plugin for Backstage

1. Clone the community plugins repository:
   ```bash
   git clone https://github.com/backstage/community-plugins
   cd community-plugins/workspaces/mta
   ```

2. Update the MTA configuration in `app-config.yaml`:
   ```yaml
   mta:
     url: http://localhost:9000
     providerAuth:
       realm: tackle
       secret: backstage-provider-secret
       clientID: backstage-provider
   ```

   **Changes made:**
   - `url`: Changed to `http://localhost:9000`
   - `realm`: Changed from `mta` to `tackle`

#### 3. Setup Keycloak Client

Run the `tackle-create-keycloak-client` script to create the necessary scopes for the backstage client to access MTA:

```bash
./tackle-create-keycloak-client
```

#### That's It!

You're now up and running for development and testing of the MTA RHDH plugin.

The local MTA instance will be available at `http://localhost:9000` and the plugin will connect to it through the configured Backstage instance.

