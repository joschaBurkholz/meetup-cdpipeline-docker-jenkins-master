FROM jdk

MAINTAINER Joscha Burkholz <joscha.burkholz@mgx.de>

ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG ANSIBLE_PPA_KEY="0x6125e2a8c77f2818fb7bd15b93c4a3fd7bb9c367"
ARG WINE_PPA_KEY="0x883e8688397576b6c509df495a9a06aef9cb8db0"

# See http://pkg.jenkins-ci.org/redhat/ for actual releases
ENV JENKINS_VERSION=2.19.4 \
    JENKINS_HOME=/var/lib/jenkins \
    JENKINS_SLAVE_AGENT_PORT=50000 \
    MAVEN_VERSION=3.3.9 \
    DOCKER_VERSION=1.12.3

# Jenkins is run with user `jenkins`, uid = 3000
# If you bind mount a volume from the host or a data container, ensure you use the same uid
RUN groupadd -r docker -g 13080 && \
    groupadd -r jenkins -g 3000 && \
    useradd -u 3000 -r -g jenkins -m -d "$JENKINS_HOME" -s /bin/bash -c "Jenkins Run User" jenkins && \
    usermod -a -G docker jenkins

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME ["/var/lib/jenkins"]

# `/usr/share/jenkins/ref/` contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
# Create NPM directory
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d /usr/lib/node_modules

# Use tini as subreaper in Docker container to adopt zombie processes
# For details see https://github.com/krallin/tini/issues/8
ADD files/tini-static /bin/tini
RUN chmod +x /bin/tini

COPY files/usr/share/jenkins/ref/init.groovy.d/init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

ADD http://updates.jenkins-ci.org/download/war/${JENKINS_VERSION}/jenkins.war /usr/share/jenkins/jenkins.war
ADD http://mirror.netcologne.de/apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.zip apache-maven-${MAVEN_VERSION}-bin.zip

# Install packages
RUN INSTALL_PKGS="sudo git ssh zip unzip curl gettext python-yaml python-jinja2 python-setuptools python-psycopg2 ansible sshpass jq" && \
echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu xenial main " > /etc/apt/sources.list.d/ansible.list && \
    apt-key adv --keyserver "hkp://p80.pool.sks-keyservers.net:80" --recv-keys $ANSIBLE_PPA_KEY && \
    apt-get update && apt-get install --no-install-recommends -y $INSTALL_PKGS

# Install node
# Add i386 arch for wine (1.8+) - needed for the electron win32 build
# Add bzip2 for phantomjs
# Config npm proxy
# Add yarn


# Install Ionic
RUN curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
RUN apt-get install -y nodejs
RUN npm install -g ionic

# Install maven
RUN unzip apache-maven-${MAVEN_VERSION}-bin.zip && \
    mv apache-maven-${MAVEN_VERSION} /opt/ && \
    rm apache-maven-${MAVEN_VERSION}-bin.zip

ENV JENKINS_UC http://updates.jenkins.io/
RUN chown -R jenkins "$JENKINS_HOME" /usr/share/jenkins/ref /usr/lib/node_modules && chmod 644 /usr/share/jenkins/jenkins.war

# 8080 for main web interface, 50000 for slave agents
EXPOSE 8080 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

COPY files/usr/local/bin/jenkins.sh /usr/local/bin/jenkins.sh
RUN chown jenkins /usr/local/bin/jenkins.sh  && \
    chmod u+x /usr/local/bin/jenkins.sh

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY files/usr/local/bin/plugins.sh /usr/local/bin/plugins.sh
RUN chown jenkins /usr/local/bin/plugins.sh  && \
    chmod u+x /usr/local/bin/plugins.sh

ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# Installing docker binary
# Attention: docker.sock needs to be mounted as volume in docker-compose.yml
# see: https://issues.jenkins-ci.org/browse/JENKINS-35025
# see: https://get.docker.com/builds/
# see: https://wiki.jenkins-ci.org/display/JENKINS/CloudBees+Docker+Custom+Build+Environment+Plugin#CloudBeesDockerCustomBuildEnvironmentPlugin-DockerinDocker
# RUN curl -sSL -O https://get.docker.com/builds/Linux/x86_64/docker-latest.tgz && tar -xvzf docker-latest.tgz
RUN curl -sSL -O https://get.docker.com/builds/Linux/x86_64/docker-${DOCKER_VERSION}.tgz && tar -xvzf docker-${DOCKER_VERSION}.tgz && mv /docker/docker /usr/local/bin/docker

USER jenkins

COPY files/plugins.txt /plugins.txt
RUN /usr/local/bin/plugins.sh /plugins.txt

# Jenkins settings
COPY files/usr/share/jenkins/ref/config.xml /usr/share/jenkins/ref/config.xml
COPY files/usr/share/jenkins/ref/hudson.tasks.Maven.xml /usr/share/jenkins/ref/hudson.tasks.Maven.xml
COPY files/usr/share/jenkins/ref/org.jenkinsci.plugins.ansible.AnsibleInstallation.xml /usr/share/jenkins/ref/org.jenkinsci.plugins.ansible.AnsibleInstallation.xml
COPY files/usr/share/jenkins/ref/credentials.xml /usr/share/jenkins/ref/credentials.xml

# Maven settings
COPY files/usr/share/maven/conf/settings.xml /usr/share/maven/conf/settings.xml

# tell Jenkins that no banner prompt for pipeline plugins is needed
# see: https://github.com/jenkinsci/docker#preinstalling-plugins
RUN echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state
