# Aqua App Template

## Description

This is a project template for developing applications based on the 1inch Aqua protocol. The project includes an implementation of XYC (X*Y=C) swap using the Aqua protocol for efficient token exchanges. The template provides a ready-to-use infrastructure for creating decentralized trading applications with support for various exchange strategies and integration with the Aqua protocol for gas cost optimization.

## Installation and Setup

### Prerequisites

- Node.js (v16 or higher)
- Yarn or npm
- Git

### Clone the Repository

```bash
git clone https://github.com/1inch/aqua-app-template.git
cd aqua-app-template
```

### Install Dependencies

Using Yarn:
```bash
yarn install
```

### Compile Contracts

```bash
yarn build
```

### Run Tests

```bash
yarn test
```

### Local Development

#### Start Local Hardhat Node

In a separate terminal, start the local blockchain node:

```bash
yarn node
```

#### Deploy Contracts to Localhost

After starting the local node, in a new terminal run the deployment:

```bash
yarn deploy:localhost
```

## Project Structure

```
aqua-app-template/
├── contracts/          # Solidity contracts
│   ├── AquaImport.sol  # Aqua protocol import
│   ├── SwapExecutor.sol # Swap executor
│   └── XYCSwap.sol     # XYC swap implementation
├── scripts/            # Deployment scripts
│   └── deploy-aqua.ts  # Contract deployment script
├── test/               # Tests
│   ├── XYCSwap.test.ts # XYC swap tests
│   └── utils.ts        # Test utility functions
└── hardhat.config.ts   # Hardhat configuration
```

## Available Commands

- `yarn build` - Compile contracts
- `yarn test` - Run tests
- `npx hardhat node` - Start local Hardhat node
- `yarn deploy:localhost` - Deploy to local network
- `yarn deploy` - Deploy to selected network
- `yarn clean` - Clean compilation artifacts

## 📄 License

This project is licensed under the **LicenseRef-Degensoft-Aqua-Source-1.1**

See the [LICENSE](LICENSE) file for details.
See the [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) file for information about third-party software, libraries, and dependencies used in this project.

**Contact for licensing inquiries:**
- 📧 license@degensoft.com 
- 📧 legal@degensoft.com
