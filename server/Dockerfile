FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY schema.sql ./
COPY src ./src
ENV NODE_ENV=production PORT=8080
EXPOSE 8080
# Schema is idempotent, so applying it on every start is safe.
CMD ["sh", "-c", "node src/migrate.js && node src/index.js"]
