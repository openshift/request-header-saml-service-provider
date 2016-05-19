#!/bin/bash

# make any custom CA certs available
update-ca-trust extract

rm -rf /run/httpd/* /tmp/httpd*
exec /usr/sbin/apachectl -DFOREGROUND
