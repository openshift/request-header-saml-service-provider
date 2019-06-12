# SAML Proxy - Ansible Install

* [Introduction](#introduction)
* [Warning](#warning)
* [Setup](#setup)
* [Install Proxy](#install-proxy)
* [Update Identity Providers](#update-identity-providers)
* [Update Web Console Logout](#update-web-console-logout)
* [Debugging](#debugging)

## Introduction

Instructions for installing the SAML Proxy via Ansible.

## Warning

The Ansbile instructions are new and less tested then the manual instructions, use at your own discretion.

## Setup

### Create Ansible Inventory

We recommend you setup your inventory based on the example provided and update the username, password, and URL fields as you need.  You may also want to provide an ``ansible.cfg`` file as well.  The ``inventory`` and ``ansible.cfg`` files are currently ignored by git.  

The playbooks should be run from a bastion, or jump host, outside of the cluster itself.

```sh
mv inventory.example inventory
```

| Variable                            | Description
|-------------------------------------|------------
| `openshift_master_public_url`       | URL to your OpenShift Master Web Console
| `saml_proxy_fqdn`                   | Hostname of your saml proxy
| `saml_proxy_url`                    | Derived from the above.  Do not edit.
| `saml_proxy_namespace`              | OpenShift project namespace where you plan to deploy your saml proxy
| `remote_user_saml_attribute`        | The field name for a user's primary ID sent by your IdP
| `remote_user_name_saml_attribute`   | The field name for a user's full name sent by your IdP
| `remote_user_email_saml_attribute`  | The field name for a user's email sent by your IdP
| `remote_user_preferred_username`    | The field name for a user's preferred username sent by your IdP.  Use this when remote_user_saml_attribute is some unique identifier (e.g. a GUID) that is not typically shown to the user.  This would be the user's common username.
| `remove_htpasswd_provider`          | True if you want to remove HTPasswd Provider.  You may want to leave it False if you want to fall back to using this Provider during testing.  The OpenShift login will present you with a choice of options before proceeding during a normal login sequence.

### Login to OpenShift

Login to your OpenShift Client with a cluster-admin user from the system you will be running the playbooks from

```sh
oc login https://openshift.ocp.example.com:443
```

## Install Proxy

This creates an instance of an Apache HTTPD server with mod_auth_mellon installed, based off the current httpd24 image provided by the Red Hat Container Catalog.  If you need to debug your server, you can follow further steps in the `saml-service-provider/debug` folder.

```sh
ansible-playbook playbooks/install-saml-auth.yaml
```

## Update Identity Providers

This configures the OAuth OpenShift Provider to Proxy to your SAML Proxy provider, which in turn proxies to your IdP.  Be sure your RequestHeader fields used here match those in your saml-auth openshift.conf file.

```sh
ansible-playbook playbooks/install-oauth-on-master.yaml
```

## Update Web Console Logout

This is written ONLY for OCP 3.9 and above.  For lower, you need to update the assetConfig entries in the master-config.yaml.

```sh
ansible-playbook playbooks/update-webconsole-cm.yaml
```

## Debugging

See [Debugging](README.md#debugging).
