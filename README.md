# BTCYield - Bitcoin Staking & Yield Platform

## Overview
BTCYield is a next-generation Bitcoin staking and yield generation platform that enables users to earn sustainable yields on their Bitcoin holdings through innovative liquid staking mechanisms and AI-driven optimization strategies.

## Architecture
- **Frontend**: Next.js 14 with TypeScript
- **Backend**: NestJS microservices
- **Smart Contracts**: Solidity with Foundry
- **Database**: PostgreSQL with replication
- **Cache**: Redis with Sentinel
- **Infrastructure**: Docker, Kubernetes (k3s)

## Getting Started

### Prerequisites
- Node.js 20+
- Docker & Docker Compose
- Git

### Installation
\`\`\`bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/btcyield.git
cd btcyield

# Install dependencies
npm install

# Copy environment variables
cp .env.example .env

# Start development services
npm run docker:dev

# Run development servers
npm run dev
\`\`\`

### Project Structure
\`\`\`
btcyield/
├── apps/              # Frontend applications
│   ├── web/          # Main web app (Next.js)
│   ├── admin/        # Admin dashboard
│   └── landing/      # Marketing site
├── services/         # Backend microservices
│   ├── auth-service/
│   ├── staking-service/
│   ├── yield-service/
│   └── ...
├── packages/         # Shared packages
│   ├── ui/          # UI components
│   ├── utils/       # Utilities
│   └── types/       # TypeScript types
├── contracts/        # Smart contracts
└── infrastructure/   # DevOps configs
\`\`\`

## Development

### Available Scripts
- \`npm run dev\` - Start all services in development mode
- \`npm run build\` - Build all packages
- \`npm run test\` - Run tests
- \`npm run lint\` - Lint code
- \`npm run format\` - Format code

## Deployment
See [deployment guide](./docs/deployment/README.md) for detailed instructions.

## License
MIT