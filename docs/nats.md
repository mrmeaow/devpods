# ⚡ NATS Guide

DevPods provides NATS 2 with **JetStream** enabled for high-performance messaging.

## Connection Details

- **NATS URL**: `nats://localhost:4222`
- **Monitoring UI**: [http://localhost:8222](http://localhost:8222)

## Node.js Usage

Using `nats`.

### Installation

```bash
npm install nats
```

### Reference Implementation

```typescript
import { connect, JSONCodec } from "nats";

const natsExample = async () => {
  const nc = await connect({ servers: "nats://localhost:4222" });
  const jc = JSONCodec();

  // Simple Publish/Subscribe
  const sub = nc.subscribe("updates");
  (async () => {
    for await (const m of sub) {
      console.log(
        `[${sub.getProcessed()}]: ${JSON.stringify(jc.decode(m.data))}`,
      );
    }
  })();

  nc.publish("updates", jc.encode({ status: "ok" }));
};
```

## NestJS Usage

Using NestJS Microservices.

### Installation

```bash
npm install @nestjs/microservices nats
```

### Configuration (`main.ts`)

```typescript
import { NestFactory } from "@nestjs/core";
import { Transport, MicroserviceOptions } from "@nestjs/microservices";

async function bootstrap() {
  const app = await NestFactory.createMicroservice<MicroserviceOptions>(
    AppModule,
    {
      transport: Transport.NATS,
      options: {
        servers: ["nats://localhost:4222"],
      },
    },
  );
  await app.listen();
}
```

## JetStream Usage (CLI)

DevPods configures JetStream by default. You can interact with it using the `nats` CLI if installed on your host.

```bash
# List streams
nats stream ls --server nats://localhost:4222
```
