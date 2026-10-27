FROM node:20-slim AS build

WORKDIR /app

COPY server/package*.json ./
RUN npm ci

COPY server/tsconfig.json ./
COPY server/src/ ./src/

RUN npx tsc

FROM node:20-slim

WORKDIR /app

COPY server/package*.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

# Map data: server resolves maps from __dirname/../../maps/
# __dirname = /app/dist, so ../../maps = /maps
COPY maps/ /maps/

EXPOSE 3000

CMD ["node", "dist/index.js"]
