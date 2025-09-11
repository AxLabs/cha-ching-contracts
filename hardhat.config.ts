import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 500
      }
    }
  },
  paths: {
    sources: "contracts",
    tests: "test",
    cache: "cache",
    artifacts: "artifacts"
  },
  networks: {
    hardhat: {},
    localhost: {
      url: process.env.LOCAL_RPC_URL || "http://127.0.0.1:8545"
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    },
    calibration: {
      // Filecoin Calibration testnet (FEVM)
      // Docs: https://docs.filecoin.io/networks/calibration
      chainId: 314159,
      url: process.env.FILECOIN_CALIBRATION_RPC_URL || "https://api.calibration.node.glif.io/rpc/v1",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || ""
  }
};

export default config;


