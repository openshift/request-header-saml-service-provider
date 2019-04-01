# request-header-saml-service-provider

This project sets up OpenShift [Request header](https://docs.openshift.com/container-platform/3.11/install_config/configuring_authentication.html#RequestHeaderIdentityProvider) authentication between a SAML IdP and OpenShift with mod_auth_mellon acting as a SAML Proxy.  There are Ansible playbooks available to roll the installs automatically, but be aware they are not resilient and you may need to modify them to work with your own environment.  Contributions and improvements are always welcome.  The playbook uses RH-SSO, built upon Keycloak, as an example IdP.  It would be great to spin up a test cluster just to practice these steps and understand how everything works, prior to attempting to integrate with another IdP.  The playbooks expect a minimal cluster install with the basic httpd-auth provider.  

The high level communication flow that is created by implementing this solution is:
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

# Proxy

This proxy is a solution to proxy ONLY the OAuth login endpoint.  We do not recommend you proxy all content requested by either the Master API or the Web Console.  That would not be a good idea because the proxy likely cannot pass all request types through correctly (websockets, SPDY).  The OpenShift OAuth provider should alone be responsible for the security of the platform.

# Automated Installs

WARNING: Be sure to run this only on test environments with NO tenants!!  This is not production ready and will probably require manual adjustments based on your environment and implementation.

## Set up your Inventory

We recommend you setup your inventory based on the example provided and update the username, password, and URL fields as you need.  You may also want to provide an ``ansible.cfg`` file as well.  The ``inventory`` and ``ansible.cfg`` files are currently ignored by git.  

```
$ mv inventory.example inventory
```


## Install the IdP

This creates an instance of RH-SSO based off the 7.3 template, with no persistent volume.  This is for testing use only and none of your configuration will persist.  If your pod crashes or you destroy the pod, your certificates will be different and you will need to make adjustments to your work on the saml-auth server.  In this event, we recommend deleting everything, as in the "Clean Up" section below, and starting over.  If you already have an IdP, you could skip this step, but it might provide useful as an exercise for your understanding of how the SAML mappings work.

```
$ ansible-playbook playbooks/install-rh-sso.yaml
```

## Install the Apache Mellon Server

This creates an instance of an Apache HTTPD server with mod_auth_mellon installed, based off the current httpd24 image provided by the Red Hat Container Catalog.  If you need to debug your server, you can follow further steps in the ``saml-service-provider/debug`` folder.

```
$ ansible-playbook playbooks/install-saml-auth.yaml
```

## Install the Client on the IdP

If you chose to install the RH-SSO IdP in the previous steps, you will need to configure the saml-auth Client for the corresponding authentication Realm.  This also installs a test-user account in the realm.  

```
$ ansible-playbook playbooks/install-rh-sso-client.yaml
```

Note: because we are adding a configmap to the SSO deploymentconfig, a new instance rolls out with the update.  This in turn requires a configmap update to the saml-auth server.  When debugging, be sure both sides have the correct updates to all certificates.  

## Update the Master API Configuration

This configures the OAuth OpenShift Provider to Proxy to your SAML Proxy provider, which in turn proxies to your IdP.  Be sure your RequestHeader fields used here match those in your saml-auth openshift.conf file.  

```
$ ansible-playbook playbooks/install-oauth-on-master.yaml
```

## Update the Web Console Logout

This is written ONLY for OCP 3.9 and above.  For lower, you need to update the assetConfig entries in the master-config.yaml.  

```
$ ansible-playbook playbooks/update-webconsole-cm.yaml 
```

## Revert the Master API Configuration

Use this in the event you need to rollback to the HTPasswd provider.

```
$ ansible-playbook playbooks/revert-oauth-on-master.yaml
```

## Clean up Resources

```
oc delete project ocp-saml-proxy
oc delete project sso
oc delete is redhat-sso73-openshift -n openshift
oc delete user test-user
oc delete identity `oc get identities | grep test-user | awk '{print $1}'`
```

Note: this does not revert changes on your web console config.

# Manual Instructions
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

Setting these now will make running future steps much more of just a copy/paste exercise rather than more manual fill in the blank.

```sh
SAML_CONFIG_DIR=/etc/origin/master/proxy
SAML_UTILITY_PROJECTS_DIR=/opt/saml-utility-projects
SAML_PROXY_FQDN=saml.apps.ocp.example.com
SAML_OCP_PROJECT=ocp-saml-proxy
OPENSHIFT_MASTER_PUBLIC_URL=https://openshift.ocp.example.com
```
* `SAML_CONFIG_DIR` - directory to store all of your SAML configuration
* `UPSTREAM_PROJECTS_DIR` - directory to check out required upstream projects
* `SAML_PROXY_FQDN` - This will be the FQDN to your SAML proxy (Apache mod\_auth\_mellon), typically something like `saml.apps.ocp.example.com`.
* `SAML_OCP_PROJECT` - OpenShift project to store the SAML Proxy resources.
* `OPENSHIFT_MASTER_PUBLIC_URL` - OpenShift masters public URL. This is the URL you access the OpenShift console on. If using a port other then 443 then include `:PORT` as part of the URL.
* `ENTITY_ID` - An ID unique to your IdP. By convention this should resolve to your meta data file. In the case of the Apache Mellon container created by this project that would be `https://SAML_PROXY_FQDN/mellon/metadata`
* `ENDPOINT_URL` - The end point of the Apache Mellon service which based on the template created in this project would be  `https://SAML_PROXY_FQDN/mellon`

## Create place to store SAML config files and clone required utitility projects
```sh
mkdir ${SAML_CONFIG_DIR}
mkdir ${SAML_UTILITY_PROJECTS_DIR}
git clone https://github.com/openshift/request-header-saml-service-provider.git
```

## Create OpenShift project
```sh
oc new-project ${SAML_OCP_PROJECT} --description='SAML proxy for RequestHeader authentication to OpenShift. See https://github.com/openshift/request-header-saml-service-provider for more details.'
```

## Generate SP SAML Metadata
```sh
# Note, Secrets cannot have key names with an 'underscore' in them, so when
# creating metadata files with `mellon_create_metadata.sh` the resulting files
# must be renamed appropriately.
mellon_endpoint_url="{{ saml_auth_url }}/mellon"
mellon_entity_id="${mellon_endpoint_url}/metadata"
file_prefix="$(echo "$mellon_entity_id" | sed 's/[^0-9A-Za-z.]/_/g' | sed 's/__*/_/g')"
/opt/saml-service-provider/mellon_create_metadata.sh $mellon_entity_id $mellon_endpoint_url
mkdir ./saml-service-provider/saml2
mv ${file_prefix}.cert ./saml-service-provider/saml2/mellon.crt
mv ${file_prefix}.key ./saml-service-provider/saml2/mellon.key
mv ${file_prefix}.xml ./saml-service-provider/saml2/mellon-metadata.xml

oc create cm httpd-saml2-config --from-file=./saml-service-provider/saml2 -n ${SAML_OCP_PROJECT}
```

Script from the mod_auth_mellon package containing the file `/usr/libexec/mod_auth_mellon/mellon_create_metadata.sh`, with documentation and instructions taken from:
- https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.3/html-single/securing_applications_and_services_guide/#configuring_mod_auth_mellon_with_red_hat_single_sign_on
- https://www.keycloak.org/docs/latest/securing_apps/index.html#configuring-mod_auth_mellon-with-keycloak


## Get your IdP Provided metadata
Your IdP administrator must provide you with your IdP metadata XML file. Information they will request from you will include but not necessarily be limited to:

* Your `ENTITY_ID` - This is determined in [Set up environment variables](#set-up-environment-variables)
* Single Sign-On Service URL: https://SAML_PROXY_FQDN/mellon/postResponse
* Single Logout Service URL: https://SAML_PROXY_FQDN/mellon/logout
* Required attributes - The attributes to be provided by the IdP to the SP
  * `user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA [LDAP group sync](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html).
  * `name` - Optional. Human full name of the user. This is used for display purposes in the UI.
  * `email` - Optional. E-mail address of the user.
  * `preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

Once recieved this file should be put in `./saml-service-provider/saml2/idp-metadata.xml`

```
# Pull your IdP Metadata as necessary and place it here
curl -k -o ../saml-service-provider/saml2/idp-metadata.xml ${IDP_SAML_METADATA_URL}
```

## Configmap of SAML and IdP Metadata

```
oc create cm httpd-saml2-config --from-file=./saml-service-provider/saml2 -n ${SAML_OCP_PROJECT}
```

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

cat /etc/origin/master/proxy/system\:proxy.crt /etc/origin/master/proxy/system\:proxy.key > ${SAML_CONFIG_DIR}/httpd-ose-certs/authproxy.pem
oc create secret generic httpd-ose-certs-secret --from-file=/etc/origin/master/proxy/authproxy.pem --from-file=/etc/origin/master/proxy/ca.crt -n ${SAML_OCP_PROJECT}
```

### Create SAML Proxy Client Certificates

The saml service provider pod will itself expose a TLS endpoint.  The OpenShift
Router will use TLS passthrough to allow it to terminate the connection. 

__NOTE__: These instructions use the OCP CA to sign the cert. The other option is to get your own signed certificate. It is recomended you get an organizationally trusted CA to sign this certifcate for production use, otherwise users will see their browsers prompting them to accept this certificate when they try to log in via SAML.


```sh
mkdir /etc/origin/master/httpd-server-certs

oc adm ca create-server-cert \
  --signer-cert='/etc/origin/master/ca.crt' \
  --signer-key='/etc/origin/master/ca.key' \
  --signer-serial='/etc/origin/master/ca.serial.txt' \
  --hostnames=${SAML_PROXY_FQDN} \
  --cert=./httpd-server-certs/server.crt \
  --key=./httpd-server-certs/server.key

mv /etc/origin/master/httpd-server-certs/{server.crt,httpd.pem}
mv /etc/origin/master/httpd-server-certs/{server.key,httpd-key.pem}

oc create secret generic httpd-server-cert-secret --from-file=/etc/origin/master/httpd-server-certs/httpd.pem -n ${SAML_OCP_PROJECT}
oc create secret generic httpd-server-key-secret --from-file=/etc/origin/master/httpd-server-certs/httpd-key.pem -n ${SAML_OCP_PROJECT}
oc create secret generic httpd-server-ca-cert-secret --from-file=/etc/origin/master/ca.crt -n ${SAML_OCP_PROJECT}
```

### Create ServerName ConfigMap

This replaces the ServerName field with your defined FQDN and port from an environment variable.

```
oc create cm server-name-script --from-file ../saml-service-provider/50-update-ServerName.sh -n ${SAML_OCP_PROJECT}
```

#### Making changes to secrets
It's likely you will need to update the value of some secrets.  To do this
simply delete the secret and recreate it.  Then trigger a new deployment.

```sh
oc project ${SAML_OCP_PROJECT}
oc delete secret <secret name>
oc create secret generic <secret name> --from-file=<path>
oc rollout latest saml-auth
```

## Deploying SAML Proxy
```sh
oc project ${SAML_OCP_PROJECT}
oc process -f ../saml-auth-template.yml \
  -p=OPENSHIFT_MASTER_PUBLIC_URL=${OPENSHIFT_MASTER_PUBLIC_URL} \
  -p=PROXY_PATH=/oauth \
  -p=PROXY_DESTINATION=OPENSHIFT_MASTER_PUBLIC_URL/oauth \
  -p=APPLICATION_DOMAIN=${APPLICATION_DOMAIN} \
  -p=REMOTE_USER_SAML_ATTRIBUTE=id \
  -p=REMOTE_USER_NAME_SAML_ATTRIBUTE=name \
  -p=REMOTE_USER_EMAIL_SAML_ATTRIBUTE=email \
  -p=REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE=username \
  | oc create -f- -n ${SAML_OCP_PROJECT}
```

The template defines replicas as 1.  This pod can be scaled to multiple replicas for high availability. During testing it is recomended to remain at 1 replicate to make debugging easier.

```sh
oc scale --replicas=2 dc saml-auth
```

## Test SAML Proxy
At this point you should be able to download your SP client metadata from the Apache mod_auth_mellon server.

1. In your browser go to: https://${SAML_PROXY_FQDN}/mellon/metadata
2. Verify your `mellon-metadata.xml` downloads

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

# Debuging

## Using the debug image
This project builds the base deployment from the Red Hat supported httpd24 image found in the Red Hat Container Catalog.  It also provides a helpful, but custom, debug image if needed.  Please see the ``saml-service-provider/debug/README.adoc`` for more instructions on using it. It is very important to note this debug image should only be used during debuging and should not be used when going live in "production".

The debug image enables `mod_auth_mellon-diagnostics` and `mod_dumpio` both of which reduce performance and output security senstive logs you would not normally want in a production setting.

To use the debug image:
```sh
oc project ${SAML_OCP_PROJECT}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=httpd-debug:latest 
```

To go back to the production image:
```sh
oc project ${SAML_OCP_PROJECT}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=openshift/httpd:latest 
```

## Common Issues
Common issues you will run into while getting this to work.

### NameIDFormat
By default when you [Generate SP SAML Metadata](#generate-sp-saml-metadata) from the `mellon_create_metadata.sh` script there is no `NameIDFormat` specified. Apache [mod_auth_mellon](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml) defaults to a setting of `transient`. This `transient` setting is a good default for our SAML proxy, as it allows the server to define every visitor with a unique ID prior to establishing any ID context from your IdP.  You will probably not, however, want to use this field as any mapped value to OpenShift.  If your IdP is expecting a different setting then you could end up with errors, most likely presenting your IdP error logs.

If there is a mismatch, then update your `saml-sp.xml` with the correct `NameIDFormat` and [recreate](#making-changes-to-secrets) the `httpd-saml-config-secret` secret.

For more information on `NameIDFormat` see the mod_auth_mellon doc [4.8.5. How do you specify the NameID format in SAML?](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml).

### IdP Attribute Mapping
The variables `REMOTE_USER_SAML_ATTRIBUTE`, `REMOTE_USER_NAME_SAML_ATTRIBUTE`, `REMOTE_USER_EMAIL_SAML_ATTRIBUTE`, and `REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE` should allow you to arbitrarly set what the IdP attribute names are for those fields and map them accordingly to the RequestHeaders.

These are the defaults for this project:

* `REMOTE_USER_SAML_ATTRIBUTE=user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA LDAP group sync.
* `REMOTE_USER_NAME_SAML_ATTRIBUTE=name` - Optional. Human full name of the user. This is used for display purposes in the UI.
* `REMOTE_USER_EMAIL_SAML_ATTRIBUTE=email` - Optional. E-mail address of the user.
* `REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE=preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

If there is an issue with attributes being matched correctly you could end up seeing:

* infinite redirect loop between OCP oAuth and SAML Proxy

### clientCA not the CA that signed your SAML Proxy client certificates
If the `clientCA` value set in the [OpenShift master configuration changes](#openshift-master-configuration-changes) step is not the CA that signed the [Create SAML Proxy Client Certificates](#create-saml-proxy-client-certificates) then you could see an infinite redirect between OpenShift oAuth and SAML Proxy or other certificate errors in the browser or various logs.

### User Attributes Missing or Incorrect
Symptoms:
Logging into Openshift with the SAML provider will have a 403 Forbidden Error.
On the saml-auth pod (only the debug version) running on Openshift, you will see this line in `/etc/httpd/conf.d/mellon_diagnostics`
`am_check_permissions processing condition 0 of 1: varname="user" flags=[REG] str=".+" directive="MellonCond user .+ [REG]" failed (no OR condition) returning HTTP_FORBIDDEN`
This error is an indication that your SAML mappings coming from your IdP are not mapping correctly. The SAML property needs to be mapped as "user".

## Reducing Debug Footprint
While debuging it is helpful if you reduce the places you need to look for logs. It is then suggested that you:

1. scale the `saml-auth` service to 1 pod so there is only one place for SAML Proxy logs
2. update your load balancer for the OpenShift `masterURL` and `masterPublicURL` to only your first OpenShift master so there is only one OpenShift master to monitor for logs

## Debug logs
Helpful logs to look at while debuging.

### SAML Proxy Container
This is assuming you are using the debug image.

* `/etc/httpd/conf.d/mellon_diagnostics`
  * contains the output of `mod_auth_mellon-diagnostics`
* stdout
  * contains the output of `mod_dumpio` plus other helpful logs
  * helpful for knowing if OCP Console is at least redirecting to SAML Proxy correctly

### OpenShift Master
It helps if first you follow [Reducing Debug Footprint](#reducing-debug-footprint) so there is only one OpenShift master set of logs to look at.

* `journalctl -lafu atomic-openshift-master-api | tee > /tmp/master-api-logs`
  * useful for debuging the communication between OCP oAuth and SAML Proxy
  
### IdP
It can not be stressed enough the importance of having your local IdP administrator be involved with your debuging efforts. The speed at which you can resolve issues is expontential if you can have them monitoring the IdP logs at the same time you are doing your initial testing and reporting back what errors they see, and or, even better, screen sharing those logs with you.


# Appendix
## Terms
Helpful terms and their defintions used throughout this document.

| Term       | Meaning
|------------|--------
| SP         | Service Provider
| IdP        | Identity Provider
| SAML Proxy | The Apache mod\_mellon\_saml container deployed by these instructions to proxy the SAML communication from your IdP to OpenSHift via the RequestHeader Authentication OpenShift oAuth provider. In the context of the SAML communication the SAML proxy is also the SP even though it is acting as a go between for OpenShift.
