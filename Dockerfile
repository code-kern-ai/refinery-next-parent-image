FROM node:18-alpine as build

WORKDIR /app
COPY package*.json /app/
ENV NEXT_TELEMETRY_DISABLED 1
RUN npm install && npm cache clean --force && rm package*.json
