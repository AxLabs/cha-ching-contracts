import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const baseUri = "ipfs://";

  const TickerRegistry = await ethers.getContractFactory("TickerRegistry");
  const registry = await TickerRegistry.deploy(deployer.address);
  await registry.waitForDeployment();
  console.log("TickerRegistry:", await registry.getAddress());

  const ChaChing1155 = await ethers.getContractFactory("ChaChing1155");
  const cc = await ChaChing1155.deploy(baseUri, deployer.address);
  await cc.waitForDeployment();
  console.log("ChaChing1155:", await cc.getAddress());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});


