# 🔴 Redis Guide

DevPods provides Redis 7 with persistent storage (AOF) and **RedisInsight** for visual data management.

## Connection Details

- **Host**: `localhost`
- **Port**: `6379`
- **Password**: `devredis`
- **Web UI**: [http://localhost:8083](http://localhost:8083) (RedisInsight)

## Node.js (Express + TS) Usage

Using `ioredis` (preferred for its robust TS support and clustering features).

### Installation

```bash
npm install ioredis
```

### Reference Implementation

```typescript
import Redis from "ioredis";

const redis = new Redis({
  host: "localhost",
  port: 6379,
  password: "devredis",
});

// Example: Caching a request
app.get("/data", async (req, res) => {
  const cached = await redis.get("my-key");
  if (cached) return res.json(JSON.parse(cached));

  const data = { hello: "world" };
  await redis.set("my-key", JSON.stringify(data), "EX", 3600);
  res.json(data);
});
```

## NestJS Usage

Using `ioredis` or a dedicated wrapper.

### Installation

```bash
npm install ioredis
```

### Provider Implementation (`redis.provider.ts`)

```typescript
import { FactoryProvider } from "@nestjs/common";
import Redis from "ioredis";

export const RedisProvider: FactoryProvider = {
  provide: "REDIS_CLIENT",
  useFactory: () => {
    return new Redis({
      host: "localhost",
      port: 6379,
      password: "devredis",
    });
  },
};
```

## Useful Commands

```bash
# Enter redis-cli
podman exec -it dev-redis-pod-redis redis-cli -a devredis

# Flush everything (use with caution!)
podman exec -it dev-redis-pod-redis redis-cli -a devredis FLUSHALL
```
