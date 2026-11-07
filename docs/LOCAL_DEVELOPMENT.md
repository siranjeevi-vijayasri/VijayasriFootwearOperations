# Local Development

## Requirements
- Node.js 20.9 or newer
- npm
- Git

## Run locally
1. Clone the repository.
2. Check out `feature/operations-platform-foundation`.
3. Run `npm install`.
4. Copy `.env.example` to `.env.local`.
5. Run `npm run dev`.
6. Open http://localhost:3000.

The current dashboard is a UI foundation with placeholder values. Supabase integration and operational workflows are not implemented yet.

## Validation
- `npm run typecheck`
- `npm run lint`
- `npm run build`

## Environment safety
Use only the dedicated operations Supabase project. Do not copy the existing catalogue database URL or keys into this project. Never commit `.env.local`, database passwords, access tokens or service-role keys.
