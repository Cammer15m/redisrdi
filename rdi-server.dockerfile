FROM redislabs/redis-di-cli:v0.118.0

USER root:root

# Install necessary packages
RUN microdnf update && \
    microdnf install -y \
    openssh-server \
    curl \
    wget \
    vim \
    python3 \
    python3-pip \
    java-11-openjdk-headless \
    && microdnf clean all

# Create RDI user and directories
RUN adduser rdi && \
    mkdir -p /opt/rdi/config /opt/rdi/pipeline-config /opt/rdi/logs && \
    chown -R rdi:rdi /opt/rdi

# Copy configuration files
COPY rdi-config/ /opt/rdi/config/
COPY from-repo/redis_di_config/ /opt/rdi/pipeline-config/

# Create RDI configuration script
COPY rdi-startup.sh /opt/rdi/rdi-startup.sh
RUN chmod +x /opt/rdi/rdi-startup.sh && \
    chown rdi:rdi /opt/rdi/rdi-startup.sh

# Switch to RDI user
USER rdi:rdi
WORKDIR /opt/rdi

# Expose RDI ports
EXPOSE 8080 9443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Override any existing entrypoint and start RDI server
ENTRYPOINT []
CMD ["/opt/rdi/rdi-startup.sh"]
