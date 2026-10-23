# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Web-based inventory and tracking management system. Two separate projects:
- `inventory/`: Spring Boot 4.0.6 backend (Java 17, Maven)
- `../frontend/`: React 19 frontend (Create React App)

## Backend (inventory/)

### Commands
```bash
# Run the application
./mvnw spring-boot:run

# Build (skip tests)
./mvnw clean package -DskipTests

# Run all tests
./mvnw test

# Run a single test class
./mvnw test -Dtest=InventoryApplicationTests
```

### MySQL Setup
Before running, create the database and update `application.properties`:
```sql
CREATE DATABASE inventory_db;
```
Then set `spring.datasource.username` and `spring.datasource.password` to your MySQL credentials. Hibernate auto-creates all tables on first run (`ddl-auto=update`).

### Architecture

Standard Spring Boot layered architecture under `com.sanjose.inventory`:

```
config/         SecurityConfig (CORS + JWT auth)
controller/     REST controllers, thin, delegate to services
service/        Business logic, @Transactional
repository/     Spring Data JPA interfaces
entity/         JPA @Entity classes
exception/      ResourceNotFoundException, GlobalExceptionHandler
dto/            Request/response DTOs
```

**Domain model:**
- `EquipmentRecord`: ICT equipment item (article, itemCode, type, office, location, etc.)
- `DeviceRecord` → EquipmentRecord (ManyToOne), individual devices under an equipment record
- `TrackingLog`, movement/check-in/check-out logs linked to equipment
- `AuditLog`, system-level audit trail
- `User`, system users with roles (admin / staff)

### REST API Base URLs (all under `/api/`)
| Endpoint | Description |
|---|---|
| `/api/auth/login` | JWT login |
| `/api/auth/logout` | Logout |
| `/api/auth/me` | Current user profile |
| `/api/equipment` | CRUD equipment records |
| `/api/equipment/{id}/devices` | CRUD devices under an equipment record |
| `/api/tracking` | CRUD tracking logs |
| `/api/tracking/equipment/{id}` | Tracking logs for a specific equipment |
| `/api/audit-logs` | Read audit logs |
| `/api/users` | CRUD users |
| `/api/scanner/receive` | Mock hardware scanner endpoint |

### Security
CSRF disabled. All `/api/**` endpoints currently permit unauthenticated access (open for development). CORS allows `http://localhost:3000`.

### Dependencies
- Spring Web MVC, Spring Data JPA, Spring Security
- MySQL Connector/J, Lombok, Bean Validation

## Frontend (../frontend/)

### Commands
```bash
# Start dev server (http://localhost:3000)
npm start

# Run tests
npm test

# Production build
npm run build
```

### Stack
React 19, Create React App, React Testing Library + Jest
