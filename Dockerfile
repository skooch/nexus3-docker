# Download, extract Nexus to /tmp/sonatype/nexus
FROM azul/zulu-openjdk-alpine:8-jre-latest as downloader

ARG NEXUS_VERSION=3.55.0-01
ARG NEXUS_DOWNLOAD_URL=https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-unix.tar.gz
ARG NEXUS_DOWNLOAD_SHA256_HASH=fd6e320f781552512642bc1cbebb9c84bad2597605045932d9443bcec22cc671

# Download Nexus and other stuff we need later
# Use wget to improve performance (#11)
# Install wget
RUN apk add wget tar

WORKDIR /tmp

# Download + extract Nexus to "/tmp/sonatype/nexus" for use later
RUN wget --quiet --output-document=./nexus-${NEXUS_VERSION}-unix.tar.gz "${NEXUS_DOWNLOAD_URL}" && \
    mkdir ./sonatype && \
    # Double space separator due to busybox bug
    echo "${NEXUS_DOWNLOAD_SHA256_HASH}  nexus-${NEXUS_VERSION}-unix.tar.gz" > ./nexus-${NEXUS_VERSION}-unix.tar.gz.sha256 && \
    sha256sum ./nexus-${NEXUS_VERSION}-unix.tar.gz && \
    sha256sum -c ./nexus-${NEXUS_VERSION}-unix.tar.gz.sha256 && \
    tar -zxf ./nexus-${NEXUS_VERSION}-unix.tar.gz -C ./sonatype && \
    mv ./sonatype/nexus-${NEXUS_VERSION} ./sonatype/nexus

# Runtime image
# Logic adapted from official Dockerfile
# https://github.com/sonatype/docker-nexus3/blob/master/Dockerfile
FROM azul/zulu-openjdk-alpine:8-jre-latest

RUN apk --no-cache add sed

# Image metadata
# git commit
LABEL org.opencontainers.image.revision="-"
LABEL org.opencontainers.image.source="https://github.com/skooch/nexus3-docker"

# Setup: Rename App, Data and Work directory per official image
# App directory (/opt/sonatype/nexus)
COPY --from=downloader /tmp/sonatype /opt/sonatype
RUN \
    # Data directory (/nexus-data)
    mv /opt/sonatype/sonatype-work/nexus3 /nexus-data && \
    # Work directory (/opt/sonatype/sonatype-work/nexus3)
    ln -s /nexus-data /opt/sonatype/sonatype-work/nexus3

# Fix-up: Startup command line: Remove hard-coded memory parameters in /opt/sonatype/nexus/bin/nexus.vmoptions (per official Docker image)
RUN sed -i '/^-Xms/d;/^-Xmx/d;/^-XX:MaxDirectMemorySize/d' /opt/sonatype/nexus/bin/nexus.vmoptions

# Enable NEXUS_CONTEXT env-variable via nexus-default.properties
RUN sed -i -e 's/^nexus-context-path=\//nexus-context-path=\/\${NEXUS_CONTEXT}/g' /opt/sonatype/nexus/etc/nexus-default.properties

# Create Nexus user + group, based on official image:
#   nexus:x:200:200:Nexus Repository Manager user:/opt/sonatype/nexus:/bin/false
#   nexus:x:200:nexus
RUN addgroup -g 3000 nexus && \
    adduser \
      --system \
      --shell /bin/false \
      --home /opt/sonatype/nexus \
      --no-create-home \
      --uid 3000 \
      --ingroup nexus \
      nexus

# Data directory "/nexus-data" owned by "nexus" user
RUN chown -R nexus:nexus /nexus-data

# Data volume
VOLUME /nexus-data

EXPOSE 8081

USER nexus

# Default environment variables, adapted from upstream Dockerfile
ENV NEXUS_HOME=/opt/sonatype/nexus \
    NEXUS_DATA=/nexus-data \
    NEXUS_CONTEXT='' \
    SONATYPE_WORK=/opt/sonatype/sonatype-work \
    INSTALL4J_ADD_VM_PARAMS="-Xms2703m -Xmx2703m -XX:MaxDirectMemorySize=2703m -Djava.util.prefs.userRoot=${NEXUS_DATA}/javaprefs"

CMD ["/opt/sonatype/nexus/bin/nexus", "run"]
