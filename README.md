# request-header-saml-service-provider

This image and associated instructions are used to set up OpenShift [Request header](https://docs.openshift.com/container-platform/3.11/install_config/configuring_authentication.html#RequestHeaderIdentityProvider) authentication between a SAML IdP and OpenShift with mod_auth_mellon acting as a SAML Proxy.

The high level communication flow that is created by implimenting this solution is:
1. OCP Console
2. SAML Proxy SP (this project)
3. Your SAML IdP
4. SAML Proxy SP (this project)
5. OCP oAuth
6. OCP console

# Outline
* [Outline](#outline)
* [Authentication not Authorization](#authentication-not-authorization)
* [OpenShift Instructions](#openshift-instructions)
* [Debuging](#debuging)
* [Apendex](#apendex) 

# Authentication not Authorization

This solution will implement SAML-based authentication for your OpenShift cluster. For authorization, the most common solution is [Syncing groups With LDAP](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html) and ensuring the `user` identity provided by your SAML IdP matches the user's identity in your LDAP.

# OpenShift Instructions
The deployment of this pod involves loading a template and using it to create a
new application.  This running pod will mount in secrets for all custom
configuration.

## Setup
Manual setup steps to do ahead of time to make the rest of this go a lot smoother.

### Request your IdP Metadata
Skip to step [Get your IdP Provided metadata](#get-your-idp-provided-metadata) and request your IdP metadata now so you will have it by the time you need it.

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
* `SAML_PROXY_FQDN` - This will be the FQDN to your SAML proxy (Apache mod\_auth\_mellon).
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

* Your `ENTITY_ID` - This is determined in [Set up environment variables](#set-up-environment-variables)
* Single Sign-On Service URL: https://SAML_PROXY_FQDN/mellon/postResponse
* Single Logout Service URL: https://SAML_PROXY_FQDN/mellon/logout
* Required attributes - The attributes to be provided by the IdP to the SP
  * `user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA [LDAP group sync](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html).
  * `name` - Optional. Human full name of the user. This is used for display purposes in the UI.
  * `email` - Optional. E-mail address of the user.
  * `preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

An example of this for Keycloak can be seen in [testing_with_keycloak.md](keycloak/testing_with_keycloak.md#creating-the-saml-metadata).

Once recieved this file should be put in `${SAML_CONFIG_DIR}/httpd-saml-config/sp-idp-metadata.xml`

## Authentication certificate
Create the necessary certifcates for two way TLS communication between OpenShift oAuth and the SAML Proxy.

### Create OCP API Client Certficates

This certifcate is used by the saml service provider pod to make a secure
request to the Master.  Using all the defaults, a suitable file can be created
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

__NOTE__: These instructions use the OCP CA to sign the cert. The other option is to get your own signed certificate. It is recomended you get an organizationally trusted CA to sign this certifcate for production use, otherwise users will see their browsers prompting them to accept this certificate when they try to log in via SAML.


```sh
pushd ${SAML_CONFIG_DIR}
mkdir ./httpd-server-certs

oc adm ca create-server-cert \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --hostnames=${SAML_PROXY_FQDN} \
  --cert=./httpd-server-certs/server.crt \
  --key=./httpd-server-certs/server.key
popd
```

## Create the OpenShift Secrets
All of the information generated and gathered so far needs to be put into OpenShift secrets so as they can be mounted into the SAML proxy.

```sh
pushd ${SAML_CONFIG_DIR}

oc project ${SAML_OCP_PROJECT}
oc secrets new httpd-saml-config-secret ./httpd-saml-config
oc secrets new httpd-ose-certs-secret ./httpd-ose-certs
oc secrets new httpd-server-certs-secret ./httpd-server-certs

# NOTE: if using your owned signed cert then replace the OpenShift CA path with your CA.
oc secrets new httpd-server-ca-cert-secret /etc/origin/master/ca.crt

popd
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
  -p PROXY_DESTINATION=https://${OPENSHIFT_MASTER_PUBLIC_URL}/oauth/ \
  | oc create -f -
```

The template defines replicas as 0.  This pod can be scaled to multiple replicas for high availability. During testing it is recomended to scale to only 1 replicate to make finding logs easier and then scale up from there.

```sh
oc scale --replicas=2 dc saml-auth
```

## Test SAML Proxy
At this point you should be able to download your SP client metadata from the Apache mod_auth_mellon server.

1. In your browser go to: https://${SAML_PROXY_FQDN}/mellon/metadata
2. verify your `saml-sp.xml` downloads

## OpenShift master configuration changes

The following changes need to take place on the `/etc/origin/master/master-config.yaml` on all of our masters. You will need to do the string replacements yourself.
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

At this point you can either manually build the image or pull it from another location.

# Debuging
It is all but 100% guaranteed the OCP Console -> SAML Proxy SP -> Your SAML IdP -> SAML Proxy SP -> OCP oAuth -> OCP console workflow implemented by these instructions will not work on the first try, and therefore here are some steps for debugging.

## Using the debug image
This project provides, and automatically builds (assuming you followed these instructions) a helpful debug image. It is very important to note this debug image should only be used during debuging and should not be used when going live in "production".

The debug image enables `mod_auth_mellon-diagnostics` and `mod_dumpio` both of which reduce performance and output security senstive logs you would not normally want in a production setting.

To use the debug image:
```sh
oc project ${SAML_OCP_PROJECT}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=saml-service-provider-debug:latest 
```

To go back to the production image:
```sh
oc project ${SAML_OCP_PROJECT}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=saml-service-provider:latest 
```

## Common Issues
Common issues you will run into while getting this to work.

### NameIDFormat
By default when you [Generate SP SAML Metadata](#generate-sp-saml-metadata) there is no `NameIDFormat` specified. Apache [mod_auth_mellon](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml) defaults to a setting of `transient`. If your IdP is expecting a different setting then you could end up with errors, most likely presenting your IdP error logs.

If there is a mismatch, then manually update your `saml-sp.xml` with the correct `NameIDFormat` and [recreate](#making-changes-to-secrets) the `httpd-saml-config-secret` secrete.

For more information on `NameIDFormat` see the mod_auth_mellon doc [4.8.5. How do you specify the NameID format in SAML?](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml).

### IdP Attribute names missmatch
In theory the `REMOTE_USER_SAML_ATTRIBUTE`, `REMOTE_USER_NAME_SAML_ATTRIBUTE`, `REMOTE_USER_EMAIL_SAML_ATTRIBUTE`, and `REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE` should allow you to arbitrarly set what the IdP attribute names are for those fields and map them accordingly to the RequestHeaders, in practice, this doesn't seem to work and can cause confusion. It is recomended (possibly required) that the IdP attributes returned exactly match:

* `user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA LDAP group sync.
* `name` - Optional. Human full name of the user. This is used for display purposes in the UI.
* `email` - Optional. E-mail address of the user.
* `preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

If there is an issue with attributes being matched correctly you could end up seeing:

* infinite redirect loop between OCP oAuth and SAML Proxy
* SAML Proxy debug container `/var/log/httpd/error_log` will show that the ResponseHeaders are not being set correctly even though the `/var/log/httpd/mellon_diagnostics` show your attributes coming back from the IdP

### clientCA not the CA that signed your SAML Proxy client certificates
if the `clientCA` value set in the [OpenShift master configuration changes](#openshift-master-configuration-changes) step is not the CA that signed the [Create SAML Proxy Client Certificates](#create-saml-proxy-client-certificates) then you could see an infinite redirect between OpenShift oAuth and SAML Proxy or other certificate errors in the browser or various logs.

### User Attributes Missing or Incorrect
Symptoms:
Logging into Openshift with the SAML provider will have a 403 Forbidden Error.
On the saml-auth pod (only the debug version) running on Openshift, you will see this line in `/var/log/httpd/mellon_diagnostics`
`am_check_permissions processing condition 0 of 1: varname="user" flags=[REG] str=".+" directive="MellonCond user .+ [REG]" failed (no OR condition) returning HTTP_FORBIDDEN`
This error is an indication that your SAML mappings coming from your IdP are not mapping correctly. The SAML property needs to be mapped as "user". See [testing_with_keycloak.md](keycloak/testing_with_keycloak.md#mapping-the-data-from-keycloak-to-mod_auth_mellon)

## Reducing Debug Footprint
While debuging it is helpful if you reduce the places you need to look for logs. It is then suggested that you:

1. scale the `saml-auth` service to 1 pod so there is only one place for SAML Proxy logs
2. update your load balancer for the OpenShift `masterURL` and `masterPublicURL` to only your first OpenShift master so there is only one OpenShift master to monitor for logs

## Debug logs
Helpful logs to look at while debuging.

### SAML Proxy Container
This is assuming you are using the debug image.

* `/var/log/httpd/mellon_diagnostics`
  * contains the output of `mod_auth_mellon-diagnostics`
* `/var/log/httpd/error_log`
  * contains the output of `mod_dumpio` plus other helpful logs
* `/var/log/httpd/ssl_access_log`
  * helpful for knowing if OCP Console is at least redirecting to SAML Proxy correctly

### OpenShift Master
It helps if first you follow [Reducing Debug Footprint](#reducing-debug-footprint) so there is only one OpenShift master set of logs to look at.

* `journalctl -lafu atomic-openshift-master-api | tee > /tmp/master-api-logs`
  * useful for debuging the communication between OCP oAuth and SAML Proxy
  
### IdP
It can not be stressed enough the importance of having your local IdP administrator be involved with your debuging efforts. The speed at which you can resolve issues is expontential if you can have them monitoring the IdP logs at the same time you are doing your initial testing and reporting back what errors they see, and or, even better, screen sharing those logs with you.


# Apendex
## Terms
Helpful terms and their defintions used throughout this document.

| Term       | Meaning
|------------|--------
| SP         | Service Provider
| IdP        | Identity Provider
| SAML Proxy | The Apache mod\_mellon\_saml container deployed by these instructions to proxy the SAML communication from your IdP to OpenSHift via the RequestHeader Authentication OpenShift oAuth provider. In the context of the SAML communication the SAML proxy is also the SP even though it is acting as a go between for OpenShift.

## Manually building the docker images
The required images are automatically built by the `saml-auth-template.yml` in the [Deploying SAML Proxy](#deploying-saml-proxy) step so manually building the image is only needed if you want to experiment locally.

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
