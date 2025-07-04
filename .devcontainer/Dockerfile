ARG PWSH_VERSION=7.4
ARG DIST_VERSION=debian-11
ARG ARCHITECTURE=x64

# Use a PWSH included image from docker hub
FROM mcr.microsoft.com/powershell:${PWSH_VERSION}-${DIST_VERSION}

ARG PSREPOSITORY=PSGallery

# We do not wish to sent telemetry
ENV POWERSHELL_TELEMETRY_OPTOUT=1

# Update OS
RUN \
  apt-get update && \
  apt-get -y install ca-certificates curl apt-transport-https lsb-release gnupg curl unzip git dos2unix

# Download & Install latest version of BICEP
RUN curl -Lo bicep https://github.com/Azure/bicep/releases/latest/download/bicep-linux-x64 && chmod +x ./bicep && mv ./bicep /usr/local/bin/bicep

RUN \
  # Install PS modules from PSGallery (~500MB)
  pwsh -Command Set-PSRepository -Name "${PSREPOSITORY}" -InstallationPolicy "Trusted" && \
  pwsh -Command Install-Module -Name "Pester" -Scope "AllUsers" -AllowClobber -Repository "${PSREPOSITORY}"

# Install/Get IPM
RUN curl -Lo /tmp/ipm.tar.gz https://github.com/ipmhubio/ipm/releases/latest/download/ipm-linux-x64-full.tar.gz && tar -xzf /tmp/ipm.tar.gz -C /usr/local/bin && rm /tmp/ipm.tar.gz && chmod +x /usr/local/bin/ipm

# Get required powershell modules
RUN \
  pwsh -Command Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted" && \
  pwsh -Command Install-Module -Name "Pester" -Scope "AllUsers" -AllowClobber -Repository "PSGallery"

RUN \
  mkdir -p /workingfolder && chmod 777 /workingfolder && \
  mkdir -p /workingfolder/avm && chmod 777 /workingfolder/avm && \
  mkdir -p /workingfolder/build && chmod 777 /workingfolder/build && \
  mkdir -p /workingfolder/build-publish && chmod 777 /workingfolder/build-publish && \
  mkdir -p /workingfolder/build-tests && chmod 777 /workingfolder/build-tests

RUN git config --global --add safe.directory /workingfolder/avm
RUN git config --global --add safe.directory /workingfolder/build
RUN git config --global --add safe.directory /workingfolder/build-publish

VOLUME [ "/workingfolder/src" ]

COPY entrypoint.sh /entrypoint.sh
COPY run-build.sh /run-build.sh
COPY run-build-publish.sh /run-build-publish.sh
COPY run-build-tests.sh /run-build-tests.sh
RUN chmod +x /entrypoint.sh /run-build.sh /run-build-publish.sh /run-build-tests.sh && dos2unix /run-build.sh && dos2unix /run-build-publish.sh && dos2unix /run-build-tests.sh

ENTRYPOINT ["/entrypoint.sh"]

SHELL ["pwsh", "-Command"]