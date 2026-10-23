# Multi-stage build for React + Vite frontend
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /build

# Copy package files from frontend subdir
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci

# Copy source
COPY frontend/ ./

# Vite bakes import.meta.env.VITE_* values into the bundle at build time, not
# runtime - a docker-compose `environment:` entry on the final container has no
# effect (the static files are already built). Must come in as a build ARG.
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL

# Build application
RUN npm run build

# Stage 2: Serve
FROM node:20-alpine
WORKDIR /app

# Install serve to serve static build
RUN npm install -g serve

# Create non-root user
RUN addgroup -S app && adduser -S app -G app

# Copy built app from builder
COPY --from=builder /build/dist ./dist

# Set ownership
RUN chown -R app:app /app

# Switch to non-root user
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:3000/ || exit 1

# Expose port
EXPOSE 3000

# Run application
CMD ["serve", "-s", "dist", "-l", "3000"]
