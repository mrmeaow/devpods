# 📊 Seq Guide

DevPods includes **Seq** for structured log search and analysis. Seq is perfect for debugging distributed systems and complex application logic.

## Connection Details

- **Ingest/UI API**: [http://localhost:5341](http://localhost:5341)
- **Authentication**: None (configured for development)

## Node.js Usage

Using `winston` and the Seq transport.

### Installation

```bash
npm install winston @datalust/winston-seq
```

### Reference Implementation

```typescript
import winston from "winston";
import { SeqTransport } from "@datalust/winston-seq";

const logger = winston.createLogger({
  level: "info",
  transports: [
    new SeqTransport({
      serverUrl: "http://localhost:5341",
      onError: (e) => console.error(e),
      handleExceptions: true,
      handleRejections: true,
    }),
  ],
});

// Structural logging example
logger.info("User Logged In", {
  UserId: 123,
  IpAddress: "127.0.0.1",
  AppVersion: "1.0.0",
});
```

## NestJS Usage

Integrated with NestJS logging.

### Installation

```bash
npm install @datalust/winston-seq nest-winston winston
```

### Configuration (`main.ts`)

```typescript
import { NestFactory } from "@nestjs/core";
import { WinstonModule } from "nest-winston";
import { SeqTransport } from "@datalust/winston-seq";

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    logger: WinstonModule.createLogger({
      transports: [
        new SeqTransport({
          serverUrl: "http://localhost:5341",
        }),
      ],
    }),
  });
  await app.listen(3000);
}
```

## Useful Commands

```bash
# Check Seq logs (container internal)
podman logs -f dev-seq-pod-seq
```
