# request-header-saml-service-provider

* [Introduction](#introduction)
* [Install Instructions](#install-instructions)
* [Debugging](#debugging)
* [Appendix](#appendix)

## Introduction

This project sets up OpenShift [Request header](https://docs.openshift.com/container-platform/3.11/install_config/configuring_authentication.html#RequestHeaderIdentityProvider) authentication between a SAML IdP and OpenShift with mod_auth_mellon acting as a SAML Proxy.

The high level communication flow that is created by implementing this solution is:
1. OCP Console
2. SAML Proxy SP
3. Your SAML IdP
4. SAML Proxy SP
5. OCP oAuth
6. OCP console

### Authentication not Authorization

This solution will implement SAML-based authentication for your OpenShift cluster. For authorization, the most common solution is [Syncing groups With LDAP](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html) and ensuring the `user` identity provided by your SAML IdP matches the user's identity in your LDAP.

### Proxy

This proxy is a solution to proxy ONLY the OpenShift OAuth login endpoint.  We do not recommend you proxy all OpenShift content requested from either the Master API or the Web Console.  That would not be a good idea because the proxy likely cannot pass all request types through correctly (websockets, SPDY).  The OpenShift OAuth provider should alone be responsible for the security of the platform.

### RH-SSO

If the environment you are testing this in does not already have a SAML Identity Provider, this repository includes instructions for deploying a containerized instance of Red Hat Single Sign On (upstream Keycloak) to test against.

**WARNING**: The RH-SSO install and instructions provided here are not intended for produciton use and are intended for sandbox testing of the SAML proxy intigration only.

### Install Paths

This project provides two ways of installing the SAML proxy: 
- manual
- automated via Ansible.

In either case the instructions should be followed against a non critical cluster in your environment first to get an understanding of how they perform in your specific environment and because this project and these instructions come with no guarantee of working in your specific environment.

**WARNING**: The Ansbile instructions are new and less tested than the manual instructions, use at your own discretion.

## Install Instructions

### Get your IdP Provided metadata

If you are not using the test IdP in this project, your IdP administrator must provide you with your IdP metadata XML file. Information they will request from you will include but not necessarily be limited to:

* Your `ENTITY_ID`: the location of your metadata output
* Single Sign-On Service URL: https://SAML_PROXY_FQDN/mellon/postResponse
* Single Logout Service URL: https://SAML_PROXY_FQDN/mellon/logout
* Required attributes - The attributes to be provided by the IdP to the SP
  * `user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA [LDAP group sync](https://docs.openshift.com/container-platform/3.11/install_config/syncing_groups_with_ldap.html).
  * `name` - Optional. Human full name of the user. This is used for display purposes in the UI.
  * `email` - Optional. E-mail address of the user.
  * `preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

### Optional: Install Red Hat Single Sign on as Test Identity Provider
See [RH-SSO](rh-sso-install.md).

### Install & Configure SAML Proxy

Choose one path:
   * [Manual](saml-proxy-manual-install.md)
   * [Ansible](saml-proxy-ansible-install.md)

## Debugging

Helpful information about debugging the SAML Proxy.

### Revert the Master API Configuration

Use this in the event you need to rollback to the HTPasswd provider.

```
$ ansible-playbook playbooks/revert-oauth-on-master.yaml
```

### Clean up Resources

```
rm -rf ${SAML_CONFIG_DIR}
rm -rf ${SAML_UTILITY_PROJECTS_DIR}rm -rf ${SAML_UTILITY_PROJECTS_DIR}
oc delete project ocp-saml-proxy
oc delete project sso
oc delete is redhat-sso73-openshift -n openshift
oc delete user test-user
oc delete identity `oc get identities | grep test-user | awk '{print $1}'`
```

Note: this does not revert changes on your web console config.


### Making changes to secrets

It's likely you will need to update the value of some secrets.  To do this
simply delete the secret and recreate it.  Then trigger a new deployment.

```sh
oc project ${SAML_PROXY_NAMESPACE}
oc delete secret <secret name>
oc create secret generic <secret name> --from-file=<path>
oc rollout latest saml-auth
```

### Using the debug image

This project builds the base deployment from the Red Hat supported httpd24 image found in the Red Hat Container Catalog.  It also provides a helpful, but custom, debug image if needed.  Please see the ``saml-service-provider/debug/README.adoc`` for more instructions on using it. It is very important to note this debug image should only be used during debuging and should not be used when going live in "production".

The debug image enables `mod_auth_mellon-diagnostics` and `mod_dumpio` both of which reduce performance and output security senstive logs you would not normally want in a production setting.

To use the debug image:

```sh
oc project ${SAML_PROXY_NAMESPACE}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=httpd-debug:latest 
```

To go back to the non-debug image:
```sh
oc project ${SAML_PROXY_NAMESPACE}
oc set triggers dc/saml-auth --containers=saml-auth --from-image=openshift/httpd:latest 
```

### Common Issues
Common issues you will run into while getting this to work.

#### NameIDFormat
By default when you [Generate SP SAML Metadata](#generate-sp-saml-metadata) from the `mellon_create_metadata.sh` script there is no `NameIDFormat` specified. Apache [mod_auth_mellon](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml) defaults to a setting of `transient`. This `transient` setting is a good default for our SAML proxy, as it allows the server to define every visitor with a unique ID prior to establishing any ID context from your IdP.  You will probably not, however, want to use this field as any mapped value to OpenShift.  If your IdP is expecting a different setting then you could end up with errors, most likely presenting your IdP error logs.

If there is a mismatch, then update your `saml-sp.xml` with the correct `NameIDFormat` and [recreate](#making-changes-to-secrets) the `httpd-saml-config-secret` secret.

For more information on `NameIDFormat` see the mod_auth_mellon doc [4.8.5. How do you specify the NameID format in SAML?](https://github.com/Uninett/mod_auth_mellon/blob/master/doc/user_guide/mellon_user_guide.adoc#485-how-do-you-specify-the-nameid-format-in-saml).

#### IdP Attribute Mapping
The variables `REMOTE_USER_SAML_ATTRIBUTE`, `REMOTE_USER_NAME_SAML_ATTRIBUTE`, `REMOTE_USER_EMAIL_SAML_ATTRIBUTE`, and `REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE` should allow you to arbitrarly set what the IdP attribute names are for those fields and map them accordingly to the RequestHeaders.

These are the defaults for this project:

* `REMOTE_USER_SAML_ATTRIBUTE=user` - Required. The unique user ID for the authenticating user. This should align with the LDAP server you plan to use for authorization, AKA LDAP group sync.
* `REMOTE_USER_NAME_SAML_ATTRIBUTE=fullname` - Optional. Human full name of the user. This is used for display purposes in the UI.
* `REMOTE_USER_EMAIL_SAML_ATTRIBUTE=email` - Optional. E-mail address of the user.
* `REMOTE_USER_PREFERRED_USERNAME_SAML_ATTRIBUTE=preferred_username` - Optional. Preferred user name, if different than the immutable identity determined from the headers specified in headers.

If there is an issue with attributes being matched correctly you could end up seeing:

* infinite redirect loop between OCP oAuth and SAML Proxy

#### clientCA not the CA that signed your SAML Proxy client certificates
If the `clientCA` value set in the [OpenShift master configuration changes](#openshift-master-configuration-changes) step is not the CA that signed the [Create SAML Proxy Client Certificates](#create-saml-proxy-client-certificates) then you could see an infinite redirect between OpenShift oAuth and SAML Proxy or other certificate errors in the browser or various logs.

#### User Attributes Missing or Incorrect
Symptoms:
Logging into Openshift with the SAML provider will have a 403 Forbidden Error.
On the saml-auth pod (only the debug version) running on Openshift, you will see this line in `/etc/httpd/conf.d/mellon_diagnostics`
`am_check_permissions processing condition 0 of 1: varname="user" flags=[REG] str=".+" directive="MellonCond user .+ [REG]" failed (no OR condition) returning HTTP_FORBIDDEN`
This error is an indication that your SAML mappings coming from your IdP are not mapping correctly. The SAML property needs to be mapped as "user".

### Reducing Debug Footprint
While debuging it is helpful if you reduce the places you need to look for logs. It is then suggested that you:

1. scale the `saml-auth` service to 1 pod so there is only one place for SAML Proxy logs
2. update your load balancer for the OpenShift `masterURL` and `masterPublicURL` to only your first OpenShift master so there is only one OpenShift master to monitor for logs

### Debug logs
Helpful logs to look at while debuging.

#### SAML Proxy Container
This is assuming you are using the debug image.

* `/etc/httpd/conf.d/mellon_diagnostics`
  * contains the output of `mod_auth_mellon-diagnostics`
* stdout
  * contains the output of `mod_dumpio` plus other helpful logs
  * helpful for knowing if OCP Console is at least redirecting to SAML Proxy correctly

#### OpenShift Master
It helps if first you follow [Reducing Debug Footprint](#reducing-debug-footprint) so there is only one OpenShift master set of logs to look at.

* `journalctl -lafu atomic-openshift-master-api | tee > /tmp/master-api-logs`
  * useful for debuging the communication between OCP oAuth and SAML Proxy
  
#### IdP
It can not be stressed enough the importance of having your local IdP administrator be involved with your debuging efforts. The speed at which you can resolve issues is expontential if you can have them monitoring the IdP logs at the same time you are doing your initial testing and reporting back what errors they see, and or, even better, screen sharing those logs with you.


## Appendix
### Terms
Helpful terms and their defintions used throughout this document.

| Term       | Meaning
|------------|--------
| SP         | Service Provider
| IdP        | Identity Provider
| SAML Proxy | The Apache mod\_mellon\_saml container deployed by these instructions to proxy the SAML communication from your IdP to OpenSHift via the RequestHeader Authentication OpenShift oAuth provider. In the context of the SAML communication the SAML proxy is also the SP even though it is acting as a go between for OpenShift.
| RH-SSO     | Red Hat Single Sign On, the Red Hat product of the Keyclock project.
