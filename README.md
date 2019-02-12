# README

This Docker image is used for SAML authentication.

# Terms
Helpful terms and their defintions used throughout thid document.

| Term       | Meaning
|------------|--------
| SP         | Service Provider
| IdP        | Identity Provider
| SAML Proxy | The Apache mod\_mellon\_saml container deployed by these instructions to proxy the SAML communication from your IdP to OpenSHift via the RequestHeader Authentication OpenShift oAuth provider. In the context of the SAML communication the SAML proxy is also the SP even though it is acting as a go between for OpenShift. 

# OpenShift Instructions
The deployment of this pod involves loading a template and using it to create a
new application.  This running pod will mount in secrets for all custom
configuration.

## Setup
Manual setups steps to make the rest of this go a lot smoother.

### Request your IdP Metadata
Skip to setp [Get your IdP Provided metadata](#Get your IdP Provided metadata) and request your IdP metadata now so you will have it by the time you need it.

### Log into first master and SUDO to root
All of this will be done on your first OpenShift master. While doing work directly on an OpenShift master is typically discouraged, you need access to files that live on the first master to complete this procedure, you will also need to be root, or be able to sudo to root, to access the required files.

### Set up environment variables

Setting these now will make running future steps much more of just a copy/paste exersize rather then more manual fill in the blank.

```sh
SAML_CONFIG_DIR=~/saml-config
SAML_UTILITY_PROJECTS_DIR=~/saml-utility-projects
SAML_PROXY_FQDN=saml-proxy.CHANGE.ME
SAML_OCP_PROJECT=ocp-saml-proxy
OPENSHIFT_MASTER_PUBLIC_URL=
ENTITY_ID=https://${SAML_PROXY_FQDN}/mellon/metadata
ENDPOINT_URL=https://${SAML_PROXY_FQDN}/mellon
```
* `SAML_CONFIG_DIR` - directory to store all of your SAML configuration
* `UPSTREAM_PROJECTS_DIR` - directory to check out required upstream projects
* `SAML_PROXY_FQDN` - This will be the FQDN to your SAML proxy (Apache mod_auth_mellon).
                      This will typically be something like `saml-proxy.MY-OCP-WILDCARD-DOMAIN`.
                      If you have `*.apps.non-prod.example.com` as your wildcard domain for your OpenShift cluster then this value would be `saml-proxy.apps.non-prod.example.com`.
                      You could also create a vanity DNS entry and have it route to your OpenShift routers but that isn't needed or typical unless you don't have the a wildcard DNS entry for your OpenShift cluster.
* `SAML_OCP_PROJECT` - OpenShift project to store the SAML Proxy resources.
* `OPENSHIFT_MASTER_PUBLIC_URL` - OpenShift masters public URL. This is the URL you access the OpenShift console on. If using a port other then 443 then include `:PORT` as part of the URL.
* `ENTITY_ID` - An ID unique to your IdP. By convention this should resolve to your meta data file. In the case of the Apache Mellon container created by this project that would be `https://SAML_PROXY_FQDN/mellon/metadata`
* `ENDPOINT_URL` - The end point of the Apache Mellon service which based on the template created in this project would be  `https://SAML_PROXY_FQDN/mellon`

## Create place to store SAML config files and clone required utitility projects
```sh
mkdir ${SAML_CONFIG_DIR}
mkdir ${SAML_UTILITY_PROJECTS_DIR}
pushd ${SAML_UTILITY_PROJECTS_DIR}
git clone https://github.com/openshift/request-header-saml-service-provider.git
git clone https://github.com/Uninett/mod_auth_mellon.git
popd
```

## Create OpenShift project
```sh
oc new-project ${SAML_OCP_PROJECT} --description='SAML proxy for RequestHeader authentication to OpenShift. See https://github.com/openshift/request-header-saml-service-provider for more details.'
```

## Generate SP SAML Metadata
```sh
pushd ${SAML_CONFIG_DIR}
mkdir ./httpd-saml-config
pushd httpd-saml-config

${SAML_UTILITY_PROJECTS_DIR}/mod_auth_mellon/mellon_create_metadata.sh ${ENTITY_ID} ${ENDPOINT_URL}

# Note, Secrets cannot have key names with an 'underscore' in them, so when
# creating metadata files with `mellon_create_metadata.sh` the resulting files
# must be renamed appropriately.
mv *.cert saml-sp.cert
mv *.key saml-sp.key
mv *.xml saml-sp.xml
popd
popd
```

## Get your IdP Provided metadata
Your IdP administrator must provide you with your IdP metadata XML file. Information they will request from you will include but not necisarrly be limited to:

* Your ENTITY_ID - This is determined in [Set up environment variables](#Set up environment variables)
* Required attributes - The attributes to be provided by the IdP to the SP
  * `user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA [LDAP group sync](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html).
  * `name` - Optional. Human full name of the user. This is used for display purposes in the UI.
  * `email` - Optional. E-mail address of the user.
  * `preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

An example of this for Keycloak can be seen in [testing_with_keycloak.md](keycloak/testing_with_keycloak.md#creating-the-saml-metadata).

Once recieved this file should be put in `${SAML_CONFIG_DIR}/httpd-saml-config/sp-idp-metadata.xml`

## Authentication certificate
Create the necissary certifcates for two way TLS communication between OpenShift oAuth and the SAML Proxy.

### Create OCP API Client Certficates

This certifcate is used by the saml service provider pod to make a secure
request to the Master.  Using all the defaults a suitable file can be created
as follows:

```sh
oc adm create-api-client-config \
  --certificate-authority='/etc/origin/master/ca.crt' \
  --client-dir='/etc/origin/master/proxy' \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --user='system:proxy'

mkdir ${SAML_CONFIG_DIR}/httpd-ose-certs
cat /etc/origin/master/proxy/system\:proxy.crt /etc/origin/master/proxy/system\:proxy.key > ${SAML_CONFIG_DIR}/httpd-ose-certs/authproxy.pem
cp /etc/origin/master/ca.crt ${SAML_CONFIG_DIR}/httpd-ose-certs/ca.crt
```

### Create SAML Proxy Client Certificates

The saml service provider pod will itself expose a TLS endpoint.  The OpenShift
Router will use TLS passthrough to allow it to terminate the connection. 

__NOTE__: these instructions use the OCP CA to sign the cert. The other option is to get your own signed certificate.
```sh
mkdir ./httpd-server-certs

oc adm ca create-server-cert \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --hostnames=${SAML_PROXY_FQDN} \
  --cert=./httpd-server-certs/server.crt \
  --key=./httpd-server-certs/server.key
```

## Create the OpenShift Secrets
All of the information generated and gathered so far needs to be put into OpenShift Secrets so as they can be mounted into the SAML proxy.

```sh
oc project ${SAML_OCP_PROJECT}
oc secrets new httpd-saml-config-secret ./httpd-saml-config
oc secrets new httpd-ose-certs-secret ./httpd-ose-certs
oc secrets new httpd-server-certs-secret ./httpd-server-certs

# NOTE: if using your owned signed cert then replace the OpenShift CA path with your CA.
oc secrets new httpd-server-ca-cert-secret /etc/origin/master/ca.crt
```

#### Making changes to secrets
It's likely you will need to update the value of some secrets.  To do this
simply delete the secret and recreate it.  Then trigger a new deployment.

```sh
oc project ${SAML_OCP_PROJECT}
oc delete secret <secret name>
oc secrets new <secret name> <path>
oc rollout latest saml-auth
```

## Deploying SAML Proxy
```sh
oc project ${SAML_OCP_PROJECT}
oc process -f ${SAML_UTILITY_PROJECTS_DIR}/request-header-saml-service-provider/saml-auth-template.yml \
  -p APPLICATION_DOMAIN=${SAML_PROXY_FQDN} \
  -p PROXY_PATH=/oauth/ \
  -p PROXY_DESTINATION=https://${OPENSHIFT_MASTER_PUBLIC_URL}:8443/oauth/
  | oc create -f -
```

The template defines replicas as 0.  This pod can be scaled to multiple replicas for high availability. During testing it is recomended to scale to only 1 replicate to make finding logs easier and then scale up from there.

```sh
oc scale --replicas=2 dc saml-auth
```

## OpenShift master configuration changes

The following changes need to take place on the `/etc/origin/master/master-config.yaml` on all of our masters. You will need to do the string replacments yourself.
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
      loginURL: "https://SAML_PROXY_FQDN/oauth/authorize?${query}"
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
      preferredUsernameHeaders:
      - X-Remote-User-Preferred-Username
      - Remote-User-Preferred-Username
  masterCA: ca-bundle.crt
...

```

```yaml
assetConfig:
  logoutURL: "https://SAML_PROXY_FQDN/mellon/logout?ReturnTo=https://SAML_PROXY_FQDN/logged_out.html"
```

Restart the master(s) at this point for the configuration to take effect.

### Making local modifications

#### ImageStream preparation
If building the image locally or pulling from another location it's helpful to
create an ImageStream to simplify ongoing deployments.  As the cluster-admin
this can be accomplished as follows:

```
# create a project for hosting the images
oc new-project openshift3

# allow all authenticated users to pull this image
oadm policy add-cluster-role-to-group system:image-puller system:authenticated -n openshift3

```

At this point you can either manually build the image or pull it from another location.

### Manually building the docker image
Create the docker image
```sh
pushd saml-service-provider
docker build --tag=saml-service-provider -f Dockerfile .
popd
```

Create the debug docker image. This image has the `mod_auth_mellon-diagnostics` and `mod_dumpio` modules
installed and enabled to aid in troubleshooting.
This image should __NOT__ be used for perminate production deployments, but rather only troubleshooting deployments.
This image depends on the base image being built first.
```sh
pushd saml-service-provider
docker build --tag=saml-service-provider -f Dockerfile .
docker build --tag=saml-service-provider-debug -f Dockerfile.debug .
popd
```

#### Pushing the image to the internal docker registry

Since the builder service account has access to create ImageStreams in the
`openshift3` project we can use its token.

```
docker login -u unused -e unused -p `oc sa get-token builder -n openshift3` 172.30.36.214:5000

# Find the internal registry IP or use DNS. In this example 172.30.36.214 is
# the internal registry.
oc get services | grep docker-registry
docker tag <your.local.image/saml-service-provider> 172.30.36.214:5000/openshift3/saml-service-provider
docker push 172.30.36.214:5000/openshift3/saml-service-provider

# If this is your first time deploying the saml pod you will need to manually scale up
oc scale --replicas=1 dc saml-auth

```
