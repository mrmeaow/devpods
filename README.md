# 🦭 DevPods - Instant Local Infrastructure via Podman

> Local dev infrastructure in isolated **Podman pods** — one script, zero Docker Desktop, zero compose files.

```bash
curl -fsSL https://raw.githubusercontent.com/mrmeaow/devpods/main/devpods.sh | bash
```

---

## What's included

| Pod             | Services                                | Ports                      | Guide                       |
| --------------- | --------------------------------------- | -------------------------- | --------------------------- |
| `dev-pg-pod`    | PostgreSQL 16 · pgweb                   | `5432` · UI → `8081`       | [Guide](./docs/postgres.md) |
| `dev-mongo-pod` | MongoDB 7 (Replica Set) · mongo-express | `27017` · UI → `8082`      | [Guide](./docs/mongodb.md)  |
| `dev-redis-pod` | Redis 7 · RedisInsight                  | `6379` · UI → `8083`       | [Guide](./docs/redis.md)    |
| `dev-mail-pod`  | Mailpit                                 | SMTP `1025` · UI → `8025`  | [Guide](./docs/mailpit.md)  |
| `dev-seq-pod`   | Seq                                     | Ingest + UI → `5341`       | [Guide](./docs/seq.md)      |
| `dev-rmq-pod`   | RabbitMQ 3 (management)                 | AMQP `5672` · UI → `15672` | [Guide](./docs/rabbitmq.md) |
| `dev-nats-pod`  | NATS 2 + JetStream                      | `4222` · Monitor → `8222`  | [Guide](./docs/nats.md)     |
| `dev-sms-pod`   | devsms                                  | `4000` · `5153`            | [Guide](./docs/devsms.md)   |
| `dev-minio-pod` | MinIO                                   | `9000` · `9001`            | [Guide](./docs/minio.md)    |

All persistent data lives in **`~/.devpods/<pod-name>/`** — fully isolated from your project.

---

## Requirements

| Requirement                                         | Notes                                             |
| --------------------------------------------------- | ------------------------------------------------- |
| [Podman](https://podman.io/docs/installation) ≥ 4.0 | Rootless works great                              |
| macOS                                               | Podman machine is auto-initialised if missing     |
| Linux                                               | Rootless systemd socket is auto-started if needed |

No Docker. No Docker Desktop. No `sudo`.

---

## Usage

### Quickstart — boot everything

```bash
curl -fsSL https://raw.githubusercontent.com/mrmeaow/devpods/main/devpods.sh | bash
```

### Run a single pod

```bash
# via curl
curl -fsSL https://raw.githubusercontent.com/mrmeaow/devpods/main/devpods.sh | bash -s -- up pg

# or after cloning
bash devpods.sh up mongo
```

### All commands

```
bash devpods.sh <command> [pod|all]
```

| Command            | Description                               |
| ------------------ | ----------------------------------------- |
| `up [pod\|all]`    | Start pod(s) — idempotent, safe to re-run |
| `down [pod\|all]`  | Stop and remove pod(s)                    |
| `reset [pod\|all]` | Stop pod(s) **and delete all data**       |
| `status`           | Show state + endpoints for every pod      |
| `help`             | Print usage                               |

### Pod aliases

```
pg / postgres      → dev-pg-pod
mongo / mongodb    → dev-mongo-pod
redis              → dev-redis-pod
mail / mailpit     → dev-mail-pod
seq                → dev-seq-pod
rmq / rabbitmq     → dev-rmq-pod
nats               → dev-nats-pod
sms / devsms      → dev-sms-pod
minio             → dev-minio-pod
all                → every pod above
```

### Examples

```bash
bash devpods.sh up all          # boot everything
bash devpods.sh up pg mongo     # not supported yet — run separately
bash devpods.sh down redis      # stop Redis pod only
bash devpods.sh reset mongo     # wipe MongoDB data and stop
bash devpods.sh status          # pretty status table
```

---

## Connection strings

After `up`, the script prints a full cheatsheet. Quick reference:

```
PostgreSQL   postgresql://devuser:devpass@localhost:5432/devdb
pgweb        http://localhost:8081

MongoDB      mongodb://localhost:27017/?replicaSet=rs0
mongo-express http://localhost:8082  (admin / admin)

Redis        redis://:devredis@localhost:6379
RedisInsight  http://localhost:8083

Mailpit SMTP  localhost:1025
Mailpit UI    http://localhost:8025

Seq           http://localhost:5341

RabbitMQ     amqp://devuser:devpass@localhost:5672
RMQ Mgmt     http://localhost:15672  (devuser / devpass)

NATS         nats://localhost:4222
NATS Monitor  http://localhost:8222

devsms API   http://localhost:4000
devsms UI    http://localhost:5153
MinIO API    http://localhost:9000
MinIO Console http://localhost:9001
```

---

## Credentials

On first run, `~/.devpods/.env` is created with safe defaults:

```bash
# ~/.devpods/.env
PG_USER=devuser
PG_PASS=devpass
PG_DB=devdb
REDIS_PASS=devredis
RMQ_USER=devuser
RMQ_PASS=devpass
MONGO_RS=rs0
ME_USER=admin
ME_PASS=admin
MINIO_ROOT_USER=devminio
MINIO_ROOT_PASS=devminio123
MINIO_BUCKET=devsms
```

Edit that file to override anything. It is **never** committed — it lives only on your machine.

---

## Winston → Seq

```bash
npm install winston @datalust/winston-seq
```

```ts
import winston from "winston";
import { SeqTransport } from "@datalust/winston-seq";

export const logger = winston.createLogger({
  level: "debug",
  format: winston.format.combine(
    winston.format.errors({ stack: true }),
    winston.format.json(),
  ),
  transports: [
    new winston.transports.Console(),
    new SeqTransport({
      serverUrl: process.env.SEQ_URL ?? "http://localhost:5341",
      handleExceptions: true,
      handleRejections: true,
    }),
  ],
});
```

---

## Useful one-liners

```bash
# Open a psql shell
podman exec -it dev-pg-pod-postgres psql -U devuser -d devdb

# Open mongosh
podman exec -it dev-mongo-pod-mongodb mongosh

# Redis CLI
podman exec -it dev-redis-pod-redis redis-cli -a devredis

# Tail logs for any service
podman logs -f dev-seq-pod-seq
podman logs -f dev-rmq-pod-rabbitmq

# Check replica set status
podman exec -it dev-mongo-pod-mongodb mongosh --eval "rs.status()"

# Inspect all pods
podman pod ps

# MinIO health
curl -I http://localhost:9000/minio/health/live

# devsms logs
podman logs -f dev-sms-pod-devsms
```

---

## 🧪 E2E Testing

The project includes a robust E2E test suite built with **Vitest** and **tsx** to validate infrastructure readiness, specifically focusing on MongoDB Replica Set features and ACID transactions.

### Running Tests

Ensure your pods are up, then run:

```bash
npm install
npm test
```

### What's tested?

- **Replica Set Validation**: Ensures Mongo is running in `rs0` mode.
- **ACID Transactions**: Tests multi-document commits and rollbacks.
- **Concurrency**: Validates write conflicts and isolation levels.
- **Schema Resilience**: Tests implicit collection creation inside transactions.

---

## Self-healing & Resilience

The refactored `devpods.sh` includes advanced logic to ensure a smooth developer experience:

- **Pull Resilience**: Detects Docker Hub rate limits and automatically falls back to `mirror.gcr.io` for authenticated/unauthenticated pulls.
- **macOS Machine Manager**: Automatically initialises and starts Podman machines if they are missing or stopped.
- **Linux Socket Activation**: Kicks the `podman.socket` service if the daemon is unresponsive.
- **Intelligent RS Init**: MongoDB replica sets are only initiated if `rs.status()` indicates they aren't already active, making `up` perfectly idempotent.
- **Preflight Checks**: Validates images and system requirements before touching any containers, preventing partial "dirty" starts.

---

## Data layout

```
~/.devpods/
├── .env                    ← credentials (auto-created, never committed)
├── cheatsheet.txt          ← auto-generated connection summary
├── dev-pg-pod/
│   └── postgres/           ← PostgreSQL data
├── dev-mongo-pod/
│   └── mongodb/            ← MongoDB data
├── dev-redis-pod/
│   ├── redis/              ← Redis AOF
│   └── redisinsight/       ← RedisInsight state
├── dev-seq-pod/
│   └── seq/                ← Seq events
├── dev-rmq-pod/
│   └── rabbitmq/           ← RabbitMQ mnesia
└── dev-nats-pod/
    └── nats/               ← JetStream store + server.conf
```

---

## Contributing

PRs welcome. The entire setup is a single self-contained bash script — keep it that way.

1. Fork → branch → edit `devpods.sh`
2. Validate syntax: `bash -n devpods.sh`
3. Test using the E2E suite: `npm test`
4. Open a PR with a description of what pod/behaviour changed

---

## Author

Made with :heart: by [Mr.Meaow](https://mrmeaow.netlify.app)

## License

MIT
