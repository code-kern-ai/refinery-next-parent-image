ARG DHI_NODE_BUILD=dhi.io/node:20-debian12-dev
ARG DHI_NODE_RUNTIME=dhi.io/node:20-debian12

FROM ${DHI_NODE_BUILD} AS builder

WORKDIR /app

COPY package*.json /app/

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm install && npm cache clean --force && rm -f package*.json

FROM ${DHI_NODE_RUNTIME}

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=builder --chown=1000:1000 /app/node_modules /app/node_modules
