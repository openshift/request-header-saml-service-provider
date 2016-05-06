FROM rhel7
MAINTAINER Wayne Dovey <wdovey@redhat.com>

LABEL Vendor="RedHat"

RUN yum repolist --disablerepo=* && \
    yum-config-manager --disable \* > /dev/null && \
    yum-config-manager --enable rhel-7-server-rpms > /dev/null

RUN yum -y install httpd mod_ssl mod_auth_mellon

ADD openshift.conf /etc/httpd/conf.d/openshift.conf
ADD httpd.conf /etc/httpd/conf/httpd.conf
RUN rm -fr /etc/httpd/conf.d/welcome.conf
ADD ssl.conf /etc/httpd/conf.d/ssl.conf
ADD logged_out.html /var/www/html/logged_out.html
RUN mkdir -p /etc/httpd/conf/ose_certs -m 755
RUN mkdir -p /etc/httpd/conf/saml -m 755
RUN mkdir -p /etc/httpd/conf/server_certs -m 755

EXPOSE 443

ADD run-httpd.sh /run-httpd.sh
RUN chmod -v +x /run-httpd.sh

CMD ["/run-httpd.sh"]

