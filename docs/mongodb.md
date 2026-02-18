# 🍃 MongoDB Guide

DevPods provides a MongoDB 7 instance configured as a **Single-Node Replica Set** (`rs0`). This enables advanced features like multi-document ACID transactions and change streams in your local environment.

## Connection Details

- **URI**: `mongodb://localhost:27017/?replicaSet=rs0`
- **Web UI**: [http://localhost:8082](http://localhost:8082) (mongo-express)
- **Auth**: `admin` / `admin` (basic auth for UI)

## Node.js (Express + TS) Usage

Using `mongoose` with Express.

### Installation

```bash
npm install mongoose
```

### Reference Implementation (Transactions)

```typescript
import mongoose from "mongoose";

const connectDB = async () => {
  await mongoose.connect("mongodb://localhost:27017/devdb?replicaSet=rs0");
};

// ACID Transaction Example
const processOrder = async (orderData) => {
  const session = await mongoose.startSession();
  session.startTransaction();
  try {
    const order = await Order.create([orderData], { session });
    await Inventory.updateOne(
      { item: orderData.item },
      { $inc: { stock: -1 } },
      { session },
    );
    await session.commitTransaction();
  } catch (error) {
    await session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
};
```

## NestJS Usage

Using `@nestjs/mongoose`.

### Installation

```bash
npm install @nestjs/mongoose mongoose
```

### Configuration (`app.module.ts`)

```typescript
import { Module } from "@nestjs/common";
import { MongooseModule } from "@nestjs/mongoose";

@Module({
  imports: [
    MongooseModule.forRoot("mongodb://localhost:27017/devdb?replicaSet=rs0"),
  ],
})
export class AppModule {}
```

## Useful Commands

```bash
# Enter mongosh
podman exec -it dev-mongo-pod-mongodb mongosh

# Check Replica Set status
podman exec -it dev-mongo-pod-mongodb mongosh --eval "rs.status()"
```
