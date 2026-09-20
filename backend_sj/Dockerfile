# Multi-stage build for Spring Boot application
# Stage 1: Build
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /build

# Copy all project files
COPY . .

# Fix line endings (Windows → Unix) and make executable
RUN dos2unix mvnw || sed -i 's/\r$//' mvnw && chmod +x mvnw

# Build application
RUN ./mvnw clean package -DskipTests

# Stage 2: Runtime
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Create non-root user
RUN addgroup -S app && adduser -S app -G app

# Copy built JAR from builder
COPY --from=builder /build/target/*.jar app.jar

# Uploaded evidence photos live here (see the uploads_data volume in docker-compose.yml). Created in
# the image, owned by the app user, so a fresh named volume mounted over it is writable by that user.
RUN mkdir -p /app/uploads

# Set ownership
RUN chown -R app:app /app

# Switch to non-root user
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Expose port
EXPOSE 8080

# Run application
ENTRYPOINT ["java", "-jar", "app.jar"]
