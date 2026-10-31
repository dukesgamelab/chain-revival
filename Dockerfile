FROM node:20-slim AS build-server

WORKDIR /app

COPY server/package*.json ./
RUN npm ci

COPY server/tsconfig.json ./
COPY server/src/ ./src/

RUN npx tsc

FROM node:20-slim AS build-website

WORKDIR /app

COPY website/package*.json ./
RUN npm ci

COPY website/ ./

RUN npm run build

FROM node:20-slim

WORKDIR /app

COPY server/package*.json ./
RUN npm ci --omit=dev

COPY --from=build-server /app/dist ./dist

# Website: server resolves from __dirname/../../website/dist
# __dirname = /app/dist, so ../../website/dist = /website/dist
COPY --from=build-website /app/dist /website/dist

# Map data: server resolves maps from __dirname/../../maps/
# __dirname = /app/dist, so ../../maps = /maps
COPY maps/ /maps/

# Game builds: server resolves from __dirname/../../builds/
# __dirname = /app/dist, so ../../builds = /builds
# Use a wildcard so the build doesn't fail if no builds exist yet
COPY build[s]/ /builds/

EXPOSE 3000

CMD ["node", "dist/index.js"]
