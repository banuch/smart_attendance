FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY sql ./sql
COPY src ./src

RUN mkdir -p /data/uploads && chown node:node /data/uploads
USER node

ENV PORT=8080 UPLOAD_DIR=/data/uploads
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:8080/api/health || exit 1

# Applies pending migrations, then serves.
CMD ["npm", "start"]
