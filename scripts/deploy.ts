import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // Configuration: Role addresses (defaults to deployer if not specified)
  const adminAddress = process.env.ADMIN_ADDRESS || deployer.address;
  const metadataRoleAddress = process.env.METADATA_ROLE_ADDRESS || deployer.address;
  const minterRoleAddress = process.env.MINTER_ROLE_ADDRESS || deployer.address;
  const burnerRoleAddress = process.env.BURNER_ROLE_ADDRESS || deployer.address;
  const controllerRoleAddress = process.env.CONTROLLER_ROLE_ADDRESS || deployer.address;
  
  const baseUri = process.env.BASE_URI || "ipfs://";

  console.log("\nRole Configuration:");
  console.log("- Admin:", adminAddress);
  console.log("- Metadata Role:", metadataRoleAddress);
  console.log("- Minter Role:", minterRoleAddress);
  console.log("- Burner Role:", burnerRoleAddress);
  console.log("- Controller Role:", controllerRoleAddress);

  // Deploy ChaChingTickerRegistry
  console.log("\nDeploying ChaChingTickerRegistry...");
  const ChaChingTickerRegistry = await ethers.getContractFactory("ChaChingTickerRegistry");
  const registry = await ChaChingTickerRegistry.deploy(adminAddress);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress();
  console.log("ChaChingTickerRegistry deployed at:", registryAddress);

  // Grant CONTROLLER_ROLE on TickerRegistry
  const CONTROLLER_ROLE = await registry.CONTROLLER_ROLE();
  if (controllerRoleAddress !== adminAddress) {
    console.log("Granting CONTROLLER_ROLE to:", controllerRoleAddress);
    const tx1 = await registry.grantRole(CONTROLLER_ROLE, controllerRoleAddress);
    await tx1.wait();
  } else {
    console.log("Granting CONTROLLER_ROLE to admin:", controllerRoleAddress);
    const tx1 = await registry.grantRole(CONTROLLER_ROLE, controllerRoleAddress);
    await tx1.wait();
  }

  // Deploy ChaChing1155
  console.log("\nDeploying ChaChing1155...");
  const ChaChing1155 = await ethers.getContractFactory("ChaChing1155");
  const cc = await ChaChing1155.deploy(baseUri, adminAddress);
  await cc.waitForDeployment();
  const ccAddress = await cc.getAddress();
  console.log("ChaChing1155 deployed at:", ccAddress);

  // Grant roles on ChaChing1155
  const MINTER_ROLE = await cc.MINTER_ROLE();
  const BURNER_ROLE = await cc.BURNER_ROLE();
  const METADATA_ROLE = await cc.METADATA_ROLE();

  // Grant METADATA_ROLE if different from admin (admin already has it from constructor)
  if (metadataRoleAddress !== adminAddress) {
    console.log("Granting METADATA_ROLE to:", metadataRoleAddress);
    const tx2 = await cc.grantRole(METADATA_ROLE, metadataRoleAddress);
    await tx2.wait();
  }

  // Grant MINTER_ROLE
  console.log("Granting MINTER_ROLE to:", minterRoleAddress);
  const tx3 = await cc.grantRole(MINTER_ROLE, minterRoleAddress);
  await tx3.wait();

  // Grant BURNER_ROLE
  console.log("Granting BURNER_ROLE to:", burnerRoleAddress);
  const tx4 = await cc.grantRole(BURNER_ROLE, burnerRoleAddress);
  await tx4.wait();

  console.log("\n✅ Deployment complete!");
  console.log("\nDeployed Contracts:");
  console.log("- ChaChingTickerRegistry:", registryAddress);
  console.log("- ChaChing1155:", ccAddress);
  console.log("\nRoles Granted:");
  console.log("- DEFAULT_ADMIN_ROLE → ", adminAddress);
  console.log("- METADATA_ROLE → ", metadataRoleAddress);
  console.log("- MINTER_ROLE → ", minterRoleAddress);
  console.log("- BURNER_ROLE → ", burnerRoleAddress);
  console.log("- CONTROLLER_ROLE → ", controllerRoleAddress);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});


