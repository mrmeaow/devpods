import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { MongoClient, ClientSession, WriteConcern, ReadConcern, ReadPreference, ObjectId } from 'mongodb';

const uri = "mongodb://localhost:27017/?replicaSet=rs0";
const client = new MongoClient(uri);

describe('MongoDB ReplicaSet & Transactions E2E', () => {
  let dbName = "e2e_test_db";
  const IdOne = ObjectId.createFromTime(1);

  beforeAll(async () => {
    await client.connect();
    // Cleanup if needed
    await client.db(dbName).dropDatabase();
  });

  afterAll(async () => {
    await client.db(dbName).dropDatabase();
    await client.close();
  });

  it('should verify that we are connected to a Replica Set', async () => {
    const admin = client.db('admin');
    const status = await admin.command({ hello: 1 });
    
    expect(status.setName).toBe('rs0');
    expect(status.isWritablePrimary).toBe(true);
  });

  it('should support multi-document ACID transactions (Commit)', async () => {
    const db = client.db(dbName);
    const coll = db.collection('transactions_commit');
    
    const session = client.startSession();
    
    try {
      session.startTransaction({
        readConcern: { level: 'snapshot' },
        writeConcern: { w: 'majority' }
      });

      await coll.insertOne({ name: 'Alice', balance: 100 }, { session });
      await coll.insertOne({ name: 'Bob', balance: 50 }, { session });

      await session.commitTransaction();
    } catch (error) {
      await session.abortTransaction();
      throw error;
    } finally {
      await session.endSession();
    }

    const count = await coll.countDocuments();
    expect(count).toBe(2);
  });

  it('should ensure atomicity on AbortTransaction', async () => {
    const db = client.db(dbName);
    const coll = db.collection('transactions_abort');
    
    const session = client.startSession();
    
    try {
      session.startTransaction();

      await coll.insertOne({ name: 'FailedEntry' }, { session });
      
      // Simulate an error or just abort
      await session.abortTransaction();
    } catch (error) {
      // expected if we aborted due to error
    } finally {
      await session.endSession();
    }

    const doc = await coll.findOne({ name: 'FailedEntry' });
    expect(doc).toBeNull();
  });

  it('should handle write conflicts between concurrent transactions', async () => {
    const db = client.db(dbName);
    const coll = db.collection('conflicts');
    
    // Seed data
    await coll.insertOne({ _id: IdOne, val: 0 });

    const session1 = client.startSession();
    const session2 = client.startSession();

    session1.startTransaction();
    session2.startTransaction();

    // Transaction 1 updates doc
    await coll.updateOne({ _id: IdOne }, { $set: { val: 1 } }, { session: session1 });

    // Transaction 2 tries to update same doc -> This should block or fail on commit/write depending on driver behavior.
    // In MongoDB, the second write will wait for the first transaction's lock.
    // If we use a promise we can see it blocks.
    
    let t2Error: any = null;
    const t2Promise = coll.updateOne({ _id: IdOne }, { $set: { val: 2 } }, { session: session2 })
      .catch(err => { t2Error = err; });

    // Wait a bit to ensure session2 is blocked
    await new Promise(r => setTimeout(r, 500));

    // Commit transaction 1
    await session1.commitTransaction();
    await session1.endSession();

    // Now session 2 should unblock and fail with a WriteConflict error because session 1 modified it.
    await t2Promise;
    await session2.abortTransaction();
    await session2.endSession();

    expect(t2Error).toBeDefined();
    // Error code 112 is WriteConflict
    expect(t2Error.code).toBe(112);

    const finalValue = await coll.findOne({ _id: IdOne });
    expect(finalValue?.val).toBe(1); // Only transaction 1's value remains
  });

  it('should allow reading own writes within a transaction', async () => {
    const db = client.db(dbName);
    const coll = db.collection('isolation_test');
    
    const session = client.startSession();
    session.startTransaction();

    await coll.insertOne({ _id: IdOne, status: 'pending' }, { session });

    // Read inside transaction
    const inside = await coll.findOne({ _id: IdOne }, { session });
    expect(inside?.status).toBe('pending');

    // Read outside transaction (should be null or old data if it existed)
    const outside = await coll.findOne({ _id: new ObjectId(1) });
    expect(outside).toBeNull();

    await session.commitTransaction();
    await session.endSession();
  });

  it('should support multi-collection transactions', async () => {
    const db = client.db(dbName);
    const users = db.collection('users');
    const logs = db.collection('logs');

    const session = client.startSession();
    session.startTransaction();

    await users.insertOne({ username: 'john_doe' }, { session });
    await logs.insertOne({ event: 'user_created', user: 'john_doe' }, { session });

    await session.commitTransaction();
    await session.endSession();

    expect(await users.countDocuments()).toBe(1);
    expect(await logs.countDocuments()).toBe(1);
  });

  it('should handle non-existent collection creation inside transaction (Mongo 4.4+)', async () => {
    const db = client.db(dbName);
    const newCollName = `auto_created_${Date.now()}`;
    const session = client.startSession();
    
    session.startTransaction();
    
    // In modern Mongo (7.0), this is allowed.
    const coll = db.collection(newCollName);
    await coll.insertOne({ test: true }, { session });
    
    await session.commitTransaction();
    await session.endSession();

    const exists = await db.listCollections({ name: newCollName }).hasNext();
    expect(exists).toBe(true);
  });

  it('should fail when using non-transactional commands inside a transaction', async () => {
    const db = client.db(dbName);
    const session = client.startSession();
    session.startTransaction();

    try {
      // Index creation is NOT allowed in transactions for some MongoDB versions or contexts
      // Actually in 7.0 it might be, but let's try something definitely not allowed or restricted.
      // E.g. dropping a collection is definitely NOT allowed in a transaction.
      const coll = db.collection('temp_drop');
      await coll.insertOne({ a: 1 }); // Not in session to ensure it exists
      
      await expect(db.collection('temp_drop').drop({ session })).rejects.toThrow();
    } finally {
      await session.abortTransaction();
      await session.endSession();
    }
  });
});
