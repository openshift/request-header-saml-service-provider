# SAML Proxy - Manual Install

* [Introduction](#introduction)
* [Setup](#setup)
* [Install Proxy](#install-proxy)
* [Update Identity Providers](#update-identity-providers)
* [Update Web Console Logout](#update-web-console-logout)
* [Debugging](#debugging)

## Introduction

Instrutions for installing the SAML Proxy via manual steps.

## Setup

### Set environment variables

Setting these now will make running future steps much more of just a copy/paste exercise rather than more manual fill in the blank.

For the SAML Proxy:
```sh
SAML_CONFIG_DIR=/etc/origin/master/proxy
SAML_UTILITY_PROJECTS_DIR=/opt/request-header-saml-service-provider
SAML_PROXY_FQDN=saml.apps.ocp.example.com
SAML_PROXY_URL=https://${SAML_PROXY_FQDN}
SAML_OCP_PROJECT=ocp-saml-proxy
OPENSHIFT_MASTER_PUBLIC_URL=https://openshift.ocp.example.com
GIT_REPO=https://github.com/openshift/request-header-saml-service-provider
GIT_BRANCH=master
APPLICATION_DOMAIN=${SAML_PROXY_FQDN}
```

| Variable                      | Description
|-------------------------------|------------
| `SAML_CONFIG_DIR`             | directory to store all of your SAML configuration
| `SAML_UTILITY_PROJECTS_DIR`   | directory to check out required upstream projects
| `SAML_PROXY_FQDN`             | This will be the FQDN to your SAML proxy (Apache mod\_auth\_mellon), typically something like `saml.apps.ocp.example.com`.
| `SAML_PROXY_URL`              | Derived from the above.  Do not edit.
| `SAML_OCP_PROJECT`            | OpenShift project to store the SAML Proxy resources.
| `OPENSHIFT_MASTER_PUBLIC_URL` | OpenShift masters public URL. This is the URL you access the OpenShift console on. If using a port other than 443 then include `:PORT` as part of the URL.
| `GIT_REPO`                    | The git repo for this project
| `GIT_BRANCH`                  | The git branch you would like to check out.

### Create place to store SAML config files and clone required utitility projects

```sh
mkdir -p ${SAML_CONFIG_DIR}
git clone ${GIT_REPO} ${SAML_UTILITY_PROJECTS_DIR} --branch ${GIT_BRANCH}
```

### Log into first master and SUDO to root

All of this will be done on your first OpenShift master. While doing work directly on an OpenShift master is typically discouraged, you need access to files that live on the first master to complete this procedure, you will also need to be root, or be able to sudo to root, to access the required files. 


### Copy IdP Provided Metadata

If you have not already [Get your IdP Provided metadata](README.md#get_your_idp_provided_metadata).

#### Option 1: Existing External SAML IdP

Once received this file should be put in `${SAML_CONFIG_DIR}/saml2/idp-metadata.xml`.  If you choose to deploy the test IdP, you will pull this in another step later.

#### Option 2: Test RH-SSO SAML IdP

If you deployed the RH-SSO instance, pull the IdP Metadata from the server.

```
curl -k -o ${SAML_CONFIG_DIR}/saml2/idp-metadata.xml ${IDP_SAML_METADATA_URL}
```

## Install Proxy

This creates an instance of an Apache HTTPD server with mod_auth_mellon installed, based off the current httpd24 image provided by the Red Hat Container Catalog.  If you need to debug your server, you can follow further steps in the `saml-service-provider/debug` folder.

### Create the server project namespace

```sh
oc new-project ${SAML_OCP_PROJECT} --description='SAML proxy for RequestHeader authentication to OpenShift. See https://github.com/openshift/request-header-saml-service-provider for more details.'
```

### Create Apache Conf ConfigMap

Mount your Mellon Specific apache settings.  If you need to further customize your apache configuration, you can update this ``openshift.conf`` file.  You may wish to use different RequestHeader names or provide additional configuration tweaks.  

```
oc create cm httpd-mellon-conf --from-file=${SAML_UTILITY_PROJECTS_DIR}/saml-service-provider/openshift.conf -n ${SAML_OCP_PROJECT}
```

### Create ServiceProvider SAML Metadata

This script generates metadata XML for your ServiceProvider, which is used by the Mellon library and is configured in your `openshift.conf` file.  You do not have to use the certificates generated here, but the generated XML outputs will give you an example of how to form your XMLdata and add your own certificates.

```sh
# Note, Secrets cannot have key names with an 'underscore' in them, so when
# creating metadata files with `mellon_create_metadata.sh` the resulting files
# must be renamed appropriately.
mellon_endpoint_url="${SAML_PROXY_URL}/mellon"
mellon_entity_id="${mellon_endpoint_url}/metadata"
file_prefix="$(echo "$mellon_entity_id" | sed 's/[^0-9A-Za-z.]/_/g' | sed 's/__*/_/g')"
${SAML_UTILITY_PROJECTS_DIR}/saml-service-provider/mellon_create_metadata.sh $mellon_entity_id $mellon_endpoint_url
mkdir ${SAML_CONFIG_DIR}/saml2
mv ${file_prefix}.cert ${SAML_CONFIG_DIR}/saml2/mellon.crt
mv ${file_prefix}.key ${SAML_CONFIG_DIR}/saml2/mellon.key
mv ${file_prefix}.xml ${SAML_CONFIG_DIR}/saml2/mellon-metadata.xml
```

Script taken from the mod_auth_mellon package containing the file `/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh`, with documentation and instructions taken from:
- https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.3/html-single/securing_applications_and_services_guide/#configuring_mod_auth_mellon_with_red_hat_single_sign_on
- https://www.keycloak.org/docs/latest/securing_apps/index.html#configuring-mod_auth_mellon-with-keycloak

Do not use the latest script from the public GitHub repository, as it is incompatible with RH-SSO without further modifications.  

### Create ConfigMap of ServiceProvider and IdP Metadata

Create a ConfigMap to mount the certificates and metadata to the pods.

```
oc create cm httpd-saml2-config --from-file=${SAML_CONFIG_DIR}/saml2 -n ${SAML_OCP_PROJECT}
```

### Create OCP API Client Certficates

This certificate is used by the saml service provider pod to make a secure
request to the Master.  Using all the defaults, a suitable file can be created
as follows:

```sh
oc adm create-api-client-config \
  --certificate-authority='/etc/origin/master/ca.crt' \
  --client-dir=${SAML_CONFIG_DIR} \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --user='system:proxy'

cat ${SAML_CONFIG_DIR}/system\:proxy.crt ${SAML_CONFIG_DIR}/system\:proxy.key > ${SAML_CONFIG_DIR}/authproxy.pem
oc create secret generic httpd-ose-certs-secret --from-file=${SAML_CONFIG_DIR}/authproxy.pem --from-file=/etc/origin/master/proxy/ca.crt -n ${SAML_OCP_PROJECT}
```

Technically speaking you can provide your own certificate in similar format, however, the CA file must be provided in the Oauth configuration of the OpenShift Master configuration.

### Create SAML Proxy Client Certificates

The saml service provider pod will itself expose a TLS endpoint.  The OpenShift
Router will use TLS passthrough to allow it to terminate the connection.

__NOTE__: These instructions use the OCP CA to sign the cert. The other option is to get your own signed certificate. It is recomended you get an organizationally trusted CA to sign this certifcate for production use, otherwise users will see their browsers prompting them to accept this certificate when they try to log in via SAML.

Here you can use the `oc` tool to provision these certificates, but you could also use other libraries such as `openssl`.

```sh
oc adm ca create-server-cert \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --hostnames=${SAML_PROXY_FQDN} \
  --cert=${SAML_CONFIG_DIR}/httpd.pem \
  --key=${SAML_CONFIG_DIR}/httpd-key.pem

oc create secret generic httpd-server-cert-secret --from-file=${SAML_CONFIG_DIR}/httpd.pem -n ${SAML_OCP_PROJECT}
oc create secret generic httpd-server-key-secret --from-file=${SAML_CONFIG_DIR}/httpd-key.pem -n ${SAML_OCP_PROJECT}
oc create secret generic httpd-server-ca-cert-secret --from-file=/etc/origin/master/ca.crt -n ${SAML_OCP_PROJECT}
```

### Create ServerName ConfigMap

This replaces the ServerName field with your defined FQDN and port from an environment variable.

```
oc create cm server-name-script --from-file ${SAML_UTILITY_PROJECTS_DIR}/saml-service-provider/50-update-ServerName.sh -n ${SAML_OCP_PROJECT}
```

### Deploying SAML Proxy

```sh
oc process -f ${SAML_UTILITY_PROJECTS_DIR}/saml-auth-template.yml \
  -p=OPENSHIFT_MASTER_PUBLIC_URL=${OPENSHIFT_MASTER_PUBLIC_URL} \
  -p=PROXY_PATH=/oauth \
  -p=PROXY_DESTINATION=${OPENSHIFT_MASTER_PUBLIC_URL}/oauth \
  -p=APPLICATION_DOMAIN=${APPLICATION_DOMAIN} \
  -p=REMOTE_USER_SAML_ATTRIBUTE=${REMOTE_USER_SAML_ATTRIBUTE} \
  -p=REMOTE_USER_NAME_SAML_ATTRIBUTE=${REMOTE_USER_NAME_SAML_ATTRIBUTE} \
  -p=REMOTE_USER_EMAIL_SAML_ATTRIBUTE=${REMOTE_USER_EMAIL_SAML_ATTRIBUTE} \
  -p=REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE=${REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE} \
  | oc create -f- -n ${SAML_OCP_PROJECT}
```

The template defines replicas as 1.  This pod can be scaled to multiple replicas for high availability. During testing it is recomended to remain at 1 replicate to make debugging easier.

```sh
oc scale --replicas=2 dc saml-auth
```

### Test SAML Proxy
At this point you should be able to download your SP client metadata from the Apache mod_auth_mellon server.

Verify your `mellon-metadata.xml` downloads:

```
curl -k https://${SAML_PROXY_FQDN}/mellon/metadata
```

## Update Identity Providers

This configures the OAuth OpenShift Provider to Proxy to your SAML Proxy provider, which in turn proxies to your IdP.  Be sure your RequestHeader fields used here match those in your saml-auth openshift.conf file.

The following changes need to take place on the `/etc/origin/master/master-config.yaml` on all masters. 

You will need to do the string replacements yourself!

```yaml
oauthConfig:
...
  identityProviders:
  - name: SAML
    challenge: false
    login: true
    mappingMethod: add
    provider:
      apiVersion: v1
      kind: RequestHeaderIdentityProvider
      loginURL: "https://${SAML_PROXY_FQDN}/oauth/authorize?${query}"
      clientCA: /etc/origin/master/ca.crt
      headers:
      - X-Remote-User
      - Remote-User
      emailHeaders:
      - X-Remote-User-Email
      - Remote-User-Email
      nameHeaders:
      - X-Remote-User-Display-Name
      - Remote-User-Display-Name
      - X-Remote-User-Name
      - Remote-User-Name
      preferredUsernameHeaders:
      - X-Remote-User-Preferred-Username
      - Remote-User-Preferred-Username
  masterCA: ca-bundle.crt
...

```

For clusters < 3.9 update this entry in master-config.yaml as well:

```yaml
assetConfig:
  logoutURL: "${SAML_PROXY_URL}/mellon/logout?ReturnTo=${SAML_PROXY_URL}/login-ocp"
```

Restart the master(s) at this point for the configuration to take effect.

For clusters < 3.10:

```
atomic-openshift-master-api
```

For cluster >= 3.10:

```
/usr/local/bin/master-restart api
```

## Update Web Console Logout

This is written ONLY for OCP 3.9 and above.  For lower, you need to update the assetConfig entries in the master-config.yaml.

```
oc get cm webconsole-config -n openshift-web-console -o yaml --export > webconsole-config.yaml
```

Be sure this value is set, with your variables expanded: 

  logoutPublicURL: '${SAML_PROXY_URL}/mellon/logout?ReturnTo=${SAML_PROXY_URL}/login-ocp'

oc export cm webconsole-config -n openshift-web-console -o yaml > webconsole-config.yaml

oc apply -f webconsole-config.yaml -n openshift-web-console

## Debugging

See [Debugging](README.md#debugging).

