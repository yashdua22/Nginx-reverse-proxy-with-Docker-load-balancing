FROM node:20-alpine

WORKDIR /app

# package.json pehle copy karo taaki Docker layer cache kaam kare
COPY package.json ./

COPY server.js ./

# Root user se mat chalao — security best practice
USER node

EXPOSE 3000

# Health check taaki docker ps mein status dikhe
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "server.js"]