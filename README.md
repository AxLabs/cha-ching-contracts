## Cha-Ching Contracts

ERC‑1155 points system where token IDs represent Campaigns for teams, plus a ticker registry to map human‑readable tickers.

### Contracts
- **ChaChing1155**: ERC‑1155 with per‑Campaign metadata and supply tracking.
- **TickerRegistry**: Globally‑unique ticker assignment per tokenId with cooldown/timelock.

### Token IDs (Campaigns)
- Token IDs represent Campaigns, not organizations directly.
- Deterministic derivation: `uint256(keccak256(abi.encode(chainId, teamId, campaignId)))`.
- Two creation flows:
  - `createCampaignDerived(teamId, campaignId, meta)` → derives `tokenId` and creates metadata.
  - `createCampaign(tokenId, teamId, campaignId, meta)` → uses a provided `tokenId`.

### Roles and Permissions
ChaChing1155
- **DEFAULT_ADMIN_ROLE**: Grant/revoke roles.
- **METADATA_ROLE**: `createCampaign`, `createCampaignDerived`, `setCampaignMetadata`, `setURI`.
- **MINTER_ROLE**: `mint`, `mintBatch`.
- **BURNER_ROLE**: `burn`, `burnBatch`.

TickerRegistry
- **DEFAULT_ADMIN_ROLE**: `setRenamePolicy(cooldown, timelock)`.
- **CONTROLLER_ROLE**: `setTicker(tokenId, ticker)`, `finalizeTicker(tokenId)`, `clearTicker(tokenId)`.
- Behavior: tickers are uppercased, unique per chain; `renameCooldown` and `renameTimelock` govern changes.

### Build & Test
```bash
nvm use  # uses the Node version from .nvmrc
npm install
npm run build
npm test
```

### Configure Environment
Create `.env` from `.env.example` (fyi, `.env` is already in .gitignore):
```bash
PRIVATE_KEY=0x...
# Optional overrides
# FILECOIN_CALIBRATION_RPC_URL=https://api.calibration.node.glif.io/rpc/v1
# SEPOLIA_RPC_URL=
```

### Deploy
Local (Anvil/Hardhat):
```bash
npm run deploy
```

Filecoin Calibration (FEVM testnet):
```bash
# Get test FIL from faucets listed in the docs
npm run deploy:calibration
```

Network details (source: Filecoin Calibration docs):
- Chain ID: `314159`
- RPC: `https://api.calibration.node.glif.io/rpc/v1`
- WebSocket: `wss://wss.calibration.node.glif.io/apigw/lotus/rpc/v1`

Reference: Filecoin Calibration network guide — [`https://docs.filecoin.io/networks/calibration`](https://docs.filecoin.io/networks/calibration)

### Deployment Notes
- Constructors
  - `ChaChing1155(baseUri, admin)` → `baseUri` like `ipfs://`, `admin` receives admin + metadata roles initially.
  - `TickerRegistry(admin)` → `admin` receives default admin.
- The sample script deploys both with the deployer as admin.

### License

Licensed under the Apache License, Version 2.0, Copyright 2025 AxLabs. See [LICENSE](./LICENSE) for more info.


