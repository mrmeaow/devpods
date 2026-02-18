# 📧 Mailpit Guide

DevPods uses **Mailpit** as a local SMTP testing server. It captures all outgoing emails and provides a beautiful web interface to inspect them.

## Connection Details

- **SMTP Host**: `localhost`
- **SMTP Port**: `1025`
- **SMTP Auth**: None required (by default)
- **Web UI**: [http://localhost:8025](http://localhost:8025)

## Node.js Usage

Using `nodemailer`.

### Installation

```bash
npm install nodemailer
npm install -D @types/nodemailer
```

### Reference Implementation

```typescript
import nodemailer from "nodemailer";

const transporter = nodemailer.createTransport({
  host: "localhost",
  port: 1025,
  secure: false, // TLS not required for local dev
});

const sendWelcomeEmail = async (to: string) => {
  await transporter.sendMail({
    from: '"DevPods" <no-reply@devpods.local>',
    to,
    subject: "Welcome to DevPods!",
    text: "Your infrastructure is ready.",
    html: "<b>Your infrastructure is ready.</b>",
  });
};
```

## NestJS Usage

Using `@nestjs-modules/mailer`.

### Installation

```bash
npm install @nestjs-modules/mailer nodemailer
```

### Configuration (`app.module.ts`)

```typescript
import { MailerModule } from "@nestjs-modules/mailer";

@Module({
  imports: [
    MailerModule.forRoot({
      transport: {
        host: "localhost",
        port: 1025,
      },
      defaults: {
        from: '"No Reply" <noreply@example.com>',
      },
    }),
  ],
})
export class AppModule {}
```
