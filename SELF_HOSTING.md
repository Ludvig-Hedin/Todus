# Self-Hosting Todus

This guide covers running Todus locally for development or self-hosting your own instance.

## Prerequisites

- [Node.js](https://nodejs.org/en/download) (v18 or higher)
- [pnpm](https://pnpm.io) (v10 or higher)
- [Docker](https://docs.docker.com/engine/install/) (v20 or higher)

## Setup Options

### Standard Setup (Recommended)

1. **Clone and Install**

   ```bash
   git clone https://github.com/Ludvig-Hedin/Todus.git
   cd Todus

   pnpm install

   # Start local database
   pnpm docker:db:up
   ```

2. **Set Up Environment**

   - Run `pnpm nizzy env` to set up your environment variables
   - Run `pnpm nizzy sync` to sync env vars and types
   - Initialize the database: `pnpm db:push`

3. **Start the App**

   ```bash
   pnpm dev
   ```

4. **Open in Browser**

   Visit [http://localhost:3000](http://localhost:3000)

### Devcontainer Setup

1. **Clone and Install**

   ```bash
   git clone https://github.com/Ludvig-Hedin/Todus.git
   cd Todus
   ```

   Open the project in your devcontainer, then:

   ```bash
   pnpm install
   pnpm docker:db:up
   ```

2. **Set Up Environment**

   - Run `pnpm nizzy env`
   - Run `pnpm nizzy sync`
   - Initialize the database: `pnpm db:push`

3. **Start the App**

   ```bash
   pnpm dev
   ```

   Visit [http://localhost:3000](http://localhost:3000)

## Environment Setup

### 1. Better Auth

In `.env`, set `BETTER_AUTH_SECRET` to a random 32-character string:

```bash
openssl rand -hex 32
```

```env
BETTER_AUTH_SECRET=your_secret_key
```

### 2. Google OAuth (required for Gmail integration)

- Open [Google Cloud Console](https://console.cloud.google.com) and create a project.
- Enable [People API](https://console.cloud.google.com/apis/library/people.googleapis.com) and [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com).
- Create OAuth 2.0 credentials (Web application).
- Add authorized redirect URIs:
  - Development: `http://localhost:8787/api/auth/callback/google`
  - Production: `https://your-production-url/api/auth/callback/google`
- Add to `.env`:

  ```env
  GOOGLE_CLIENT_ID=your_client_id
  GOOGLE_CLIENT_SECRET=your_client_secret
  ```

- Add yourself as a test user under [Audience](https://console.cloud.google.com/auth/audience).

> **Warning:** authorized redirect URIs in Google Cloud Console must match the values in `.env` exactly (protocol, domain, and path).

### 3. Autumn (encryption)

- Sign up at [Autumn](https://useautumn.com/).
- Generate a secret key from [onboarding](https://app.useautumn.com/sandbox/onboarding) for local use, or from production mode for production.
- Add to `.env`:

  ```env
  AUTUMN_SECRET_KEY=your_autumn_secret
  ```

### 4. Twilio (SMS)

- Create a [Twilio](https://www.twilio.com/) account.
- From the dashboard collect your Account SID, Auth Token, and phone number.
- Add to `.env`:

  ```env
  TWILIO_ACCOUNT_SID=your_account_sid
  TWILIO_AUTH_TOKEN=your_auth_token
  TWILIO_PHONE_NUMBER=your_twilio_phone_number
  ```

## Environment Variables

Run `pnpm nizzy env` to bootstrap environment variables — it copies `.env.example` to `.env` and fills in the variables for you. A local connection string example lives in `.env.example`.

## Database

Todus uses PostgreSQL.

1. **Start the database**

   ```bash
   pnpm docker:db:up
   ```

   Defaults:

   - Name: `todus`
   - Username: `postgres`
   - Password: `postgres`
   - Port: `5432`

2. **Connection string**

   ```env
   DATABASE_URL="postgresql://postgres:postgres@localhost:5432/todus"
   ```

3. **Common commands**

   - `pnpm db:push` — set up database tables
   - `pnpm db:generate` — create migration files after schema changes
   - `pnpm db:migrate` — apply migrations
   - `pnpm db:studio` — open Drizzle Studio

## Sync (Durable Objects + R2)

Background: https://x.com/cmdhaus/status/1940886269950902362

User emails are stored in their Durable Object and an R2 bucket for speed. Three env vars control sync behavior:

- `DROP_AGENT_TABLES` — drop the threads table before starting a sync
- `THREAD_SYNC_MAX_COUNT` — threads to sync per page (max `500`, the driver's `maxResults` cap)
- `THREAD_SYNC_LOOP` — loop until the folder is fully synced (should be `true` in production)
