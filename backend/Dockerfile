FROM node:20-alpine

WORKDIR /app

# Install Pi CLI
RUN npm install -g @earendil-works/pi-coding-agent

# Copy backend code
COPY package*.json ./
RUN npm install --omit=dev

COPY src ./src
COPY tsconfig.json ./

# Build TypeScript
RUN npm run build

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Run the built application
CMD ["node", "dist/index.js"]
