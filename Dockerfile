FROM rhel7
MAINTAINER Wayne Dovey <wdovey@redhat.com>

LABEL Vendor="RedHat"

RUN yum -y install httpd mod_ssl mod_auth_mellon

ADD openshift.conf /etc/httpd/conf.d/openshift.conf
ADD httpd.conf /etc/httpd/conf/httpd.conf
RUN rm -fr /etc/httpd/conf.d/welcome.conf
ADD ssl.conf /etc/httpd/conf.d/ssl.conf
ADD logged_out.html /var/www/html/logged_out.html

EXPOSE 443

ADD run-httpd.sh /run-httpd.sh
RUN chmod -v +x /run-httpd.sh

CMD ["/run-httpd.sh"]
