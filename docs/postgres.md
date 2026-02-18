# 🐘 PostgreSQL Guide

DevPods provides a PostgreSQL 16 instance with **pgweb** as a lightweight web-based GUI.

## Connection Details

- **Host**: `localhost`
- **Port**: `5432`
- **User**: `devuser` (default)
- **Password**: `devpass` (default)
- **Database**: `devdb` (default)
- **Web UI**: [http://localhost:8081](http://localhost:8081)

## Node.js (Express + TS) Usage

Using `pg` (node-postgres) with Express.

### Installation

```bash
npm install pg
npm install -D @types/pg
```

### Reference Implementation

```typescript
import { Pool } from "pg";

const pool = new Pool({
  host: "localhost",
  port: 5432,
  user: "devuser",
  password: "devpass",
  database: "devdb",
});

// Example: Express Route
app.get("/users", async (req, res) => {
  try {
    const result = await pool.query("SELECT * FROM users");
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: "Database error" });
  }
});
```

## NestJS Usage

Using `@nestjs/typeorm` (recommended).

### Installation

```bash
npm install @nestjs/typeorm typeorm pg
```

### Configuration (`app.module.ts`)

```typescript
import { Module } from "@nestjs/common";
import { TypeOrmModule } from "@nestjs/typeorm";

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: "postgres",
      host: "localhost",
      port: 5432,
      username: "devuser",
      password: "devpass",
      database: "devdb",
      autoLoadEntities: true,
      synchronize: true, // Only for development!
    }),
  ],
})
export class AppModule {}
```

## Useful Commands

```bash
# Enter psql shell
podman exec -it dev-pg-pod-postgres psql -U devuser -d devdb

# Check logs
podman logs -f dev-pg-pod-postgres
```
