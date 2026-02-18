# 🐰 RabbitMQ Guide

DevPods provides RabbitMQ 3 Management (Alpine) for message-based communication.

## Connection Details

- **AMQP URL**: `amqp://devuser:devpass@localhost:5672`
- **Management UI**: [http://localhost:15672](http://localhost:15672)
- **UI Credentials**: `devuser` / `devpass`

## Node.js Usage

Using `amqplib`.

### Installation

```bash
npm install amqplib
npm install -D @types/amqplib
```

### Reference Implementation

```typescript
import amqp from "amqplib";

const connectRMQ = async () => {
  const connection = await amqp.connect(
    "amqp://devuser:devpass@localhost:5672",
  );
  const channel = await connection.createChannel();

  const queue = "task_queue";
  await channel.assertQueue(queue, { durable: true });

  // Sending a message
  channel.sendToQueue(queue, Buffer.from("Hello World!"), { persistent: true });
};
```

## NestJS Usage

Using NestJS Microservices.

### Installation

```bash
npm install @nestjs/microservices amqplib amqp-connection-manager
```

### Configuration (`main.ts`)

```typescript
import { NestFactory } from "@nestjs/core";
import { Transport, MicroserviceOptions } from "@nestjs/microservices";

async function bootstrap() {
  const app = await NestFactory.createMicroservice<MicroserviceOptions>(
    AppModule,
    {
      transport: Transport.RMQ,
      options: {
        urls: ["amqp://devuser:devpass@localhost:5672"],
        queue: "main_queue",
        queueOptions: {
          durable: false,
        },
      },
    },
  );
  await app.listen();
}
```

## Useful Commands

```bash
# Check RabbitMQ status
podman exec -it dev-rmq-pod-rabbitmq rabbitmqctl status
```
