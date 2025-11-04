import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  const baseUri = "ipfs://";

  // Deploy ChaChing1155 first
  console.log("=== Deploying ChaChing1155 ===");
  const ChaChing1155 = await ethers.getContractFactory("ChaChing1155");
  const cc = await ChaChing1155.deploy(baseUri, deployer.address, "Cha-Ching", "CHING");
  await cc.waitForDeployment();
  const ccAddress = await cc.getAddress();
  console.log("ChaChing1155 deployed at:", ccAddress);

  // Deploy ChaChingManager
  console.log("=== Deploying ChaChingManager ===");
  const ChaChingManager = await ethers.getContractFactory("ChaChingManager");
  const manager = await ChaChingManager.deploy(deployer.address);
  await manager.waitForDeployment();
  const managerAddress = await manager.getAddress();
  console.log("ChaChingManager deployed at:", managerAddress);

  // Set ChaChing1155 address on manager
  console.log("=== Setting ChaChing1155 address on manager ===");
  const tx1 = await manager.setChaChing1155(ccAddress);
  await tx1.wait();
  console.log("ChaChing1155 address set on manager");

  // Grant METADATA_ROLE to manager on ChaChing1155
  console.log("=== Granting METADATA_ROLE to manager ===");
  const METADATA_ROLE = await cc.METADATA_ROLE();
  const tx2 = await cc.grantRole(METADATA_ROLE, managerAddress);
  await tx2.wait();
  console.log("METADATA_ROLE granted to manager");

  console.log("=== Deployment Summary ===");
  console.log("ChaChing1155:", ccAddress);
  console.log("ChaChingManager:", managerAddress);
  console.log("Setup complete! Manager can now create tokens in ChaChing1155 when epochs are created.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});


