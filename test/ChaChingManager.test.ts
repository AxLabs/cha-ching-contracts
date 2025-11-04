import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ChaChingManager", function () {
  async function deployFixture() {
    const [deployer, controller, user] = await ethers.getSigners();
    const ChaChingManager = await ethers.getContractFactory("ChaChingManager");
    const manager = await ChaChingManager.deploy(deployer.address);
    await manager.waitForDeployment();

    const CONTROLLER_ROLE = await manager.CONTROLLER_ROLE();
    await manager.grantRole(CONTROLLER_ROLE, controller.address);

    return { manager, deployer, controller, user };
  }

  it("grants default admin to deployer", async function () {
    const { manager, deployer } = await loadFixture(deployFixture);
    const DEFAULT_ADMIN_ROLE = await manager.DEFAULT_ADMIN_ROLE();
    expect(await manager.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.eq(true);
  });

  it("normalizes to uppercase and validates characters/length", async function () {
    const { manager, controller } = await loadFixture(deployFixture);
    const tokenId = 1n;
    await expect(
      manager.connect(controller).setTicker(tokenId, "ab")
    ).to.be.revertedWith("ChaChingManager: invalid ticker");
    await expect(
      manager.connect(controller).setTicker(tokenId, "A_1")
    ).to.be.revertedWith("ChaChingManager: invalid ticker");
    await manager.connect(controller).setTicker(tokenId, "ching-axl-e1");
    const [pendingTicker] = await manager.getPending(tokenId);
    expect(pendingTicker).to.eq("CHING-AXL-E1");
  });

  it("enforces uniqueness with cooldown across changes", async function () {
    const { manager, controller } = await loadFixture(deployFixture);
    const tokenA = 1n;
    const tokenB = 2n;

    // shorten policies for test
    await manager.setRenamePolicy(1, 0); // cooldown 1s, timelock 0s

    // set for A
    await manager.connect(controller).setTicker(tokenA, "CHING-AXL-E1");
    await manager.connect(controller).finalizeTicker(tokenA);
    expect(await manager.getTicker(tokenA)).to.eq("CHING-AXL-E1");

    // cannot take same for B (reverts at setTicker)
    await expect(
      manager.connect(controller).setTicker(tokenB, "CHING-AXL-E1")
    ).to.be.revertedWith("ChaChingManager: ticker already taken");

    // change A to new ticker after cooldown
    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine", []);
    await manager.connect(controller).setTicker(tokenA, "CHING-AXL-E2");
    await manager.connect(controller).finalizeTicker(tokenA);
    expect(await manager.getTicker(tokenA)).to.eq("CHING-AXL-E2");

    // after A moved off E1, B can take E1
    await manager.connect(controller).setTicker(tokenB, "CHING-AXL-E1");
    await manager.connect(controller).finalizeTicker(tokenB);
    expect(await manager.getTicker(tokenB)).to.eq("CHING-AXL-E1");
  });

  it("enforces timelock before finalization", async function () {
    const { manager, controller } = await loadFixture(deployFixture);
    await manager.setRenamePolicy(0, 5); // no cooldown, timelock 5s
    const tokenId = 3n;
    await manager.connect(controller).setTicker(tokenId, "DELAY");
    await expect(manager.connect(controller).finalizeTicker(tokenId)).to.be.revertedWith("ChaChingManager: not ready");
    await ethers.provider.send("evm_increaseTime", [6]);
    await ethers.provider.send("evm_mine", []);
    await manager.connect(controller).finalizeTicker(tokenId);
    expect(await manager.getTicker(tokenId)).to.eq("DELAY");
  });

  it("rate limits changes per token and requires controller role", async function () {
    const { manager, controller, user } = await loadFixture(deployFixture);
    await manager.setRenamePolicy(10, 0); // long cooldown
    const tokenId = 7n;

    await expect(
      manager.connect(user).setTicker(tokenId, "AAA")
    ).to.be.revertedWithCustomError(manager, "AccessControlUnauthorizedAccount");

    await manager.connect(controller).setTicker(tokenId, "AAA");
    await manager.connect(controller).finalizeTicker(tokenId);

    // immediately setting again should fail due to cooldown
    await expect(
      manager.connect(controller).setTicker(tokenId, "AAB")
    ).to.be.revertedWith("ChaChingManager: cooldown");
  });

  it("clearTicker frees the name and emits events", async function () {
    const { manager, controller } = await loadFixture(deployFixture);
    await manager.setRenamePolicy(0, 0);
    const tokenId = 9n;
    await manager.connect(controller).setTicker(tokenId, "ABC");
    await expect(manager.connect(controller).finalizeTicker(tokenId))
      .to.emit(manager, "TickerSet");
    expect(await manager.getTicker(tokenId)).to.eq("ABC");

    await expect(manager.connect(controller).clearTicker(tokenId))
      .to.emit(manager, "TickerCleared");
    expect(await manager.getTicker(tokenId)).to.eq("");

    // can be re-taken by another token now
    const other = 10n;
    await manager.connect(controller).setTicker(other, "ABC");
    await manager.connect(controller).finalizeTicker(other);
    expect(await manager.getTicker(other)).to.eq("ABC");
  });
});


