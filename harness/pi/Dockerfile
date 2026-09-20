# syntax=mirror.gcr.io/docker/dockerfile:1.7

ARG SANDBOX_AGENT_IMAGE=discobox-sandbox-agent:local
FROM ${SANDBOX_AGENT_IMAGE}

ARG HARNESS_METADATA
RUN [ -n "${HARNESS_METADATA}" ] || { \
        echo "HARNESS_METADATA build argument is required" >&2; \
        exit 1; \
    }
LABEL io.discobox.image.v1=${HARNESS_METADATA}

RUN npm install -g @earendil-works/pi-coding-agent \
    && rm -rf /root/.npm \
    && install -d -m 0755 /usr/local/libexec/discobox

COPY --chmod=0644 agent.conf /usr/local/libexec/discobox/agent.conf
COPY --chmod=0755 configure.sh /usr/local/libexec/discobox/configure-pi
COPY --chmod=0755 launch.sh /usr/local/bin/discobox-harness-run
COPY --chmod=0755 prompt.sh /usr/local/bin/discobox-prompt
