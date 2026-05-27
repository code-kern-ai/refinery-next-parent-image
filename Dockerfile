ARG DHI_NODE_BUILD=dhi.io/node:20-debian12-dev@sha256:57ce14e7f0abfc500c231d8a95a19ece080cf84010a043706a7bc56705ad8ab2
ARG DHI_NODE_RUNTIME=dhi.io/node:20-debian12-dev@sha256:57ce14e7f0abfc500c231d8a95a19ece080cf84010a043706a7bc56705ad8ab2

FROM ${DHI_NODE_BUILD} AS builder

WORKDIR /app

COPY package*.json /app/

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm install && npm cache clean --force && rm -f package*.json

FROM ${DHI_NODE_RUNTIME}

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=builder --chown=65532:65532 /app/node_modules /app/node_modules

USER 65532:65532
