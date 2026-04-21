// cspell:words ECIES

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-network-helpers";
import "@typechain/hardhat";
import "hardhat-dependency-compiler";
import "solidity-coverage";
import "solidity-docgen";
import dotenv from "dotenv"


dotenv.config({ quiet: true });

const config: HardhatUserConfig = {
  docgen: {
    outputDir: "docs",
    pages: "files",
    templates: "./docs/templates",
    exclude: [
      "test"
    ]
  },
  networks: {
    custom: {
      url: process.env.ENDPOINT || "http://localhost:8545",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    }
  },
  solidity: {
    version: "0.8.30",
    settings: {
      evmVersion: "prague",
      optimizer: {
        enabled: true,
        runs: 200,
      }
    }
  },
  dependencyCompiler: {
    paths: [
      "@skalenetwork/skale-manager-interfaces/*",
      "@skalenetwork/ima-interfaces/*"
    ],
    keep: true,
  }
};

export default config;
