import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("TickerRegistry", function () {
  async function deployFixture() {
    const [deployer, controller, user] = await ethers.getSigners();
    const TickerRegistry = await ethers.getContractFactory("TickerRegistry");
    const reg = await TickerRegistry.deploy(deployer.address);
    await reg.waitForDeployment();

    const CONTROLLER_ROLE = await reg.CONTROLLER_ROLE();
    await reg.grantRole(CONTROLLER_ROLE, controller.address);

    return { reg, deployer, controller, user };
  }

  it("grants default admin to deployer", async function () {
    const { reg, deployer } = await loadFixture(deployFixture);
    const DEFAULT_ADMIN_ROLE = await reg.DEFAULT_ADMIN_ROLE();
    expect(await reg.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.eq(true);
  });

  it("normalizes to uppercase and validates characters/length", async function () {
    const { reg, controller } = await loadFixture(deployFixture);
    const tokenId = 1n;
    await expect(
      reg.connect(controller).setTicker(tokenId, "ab")
    ).to.be.revertedWith("TickerRegistry: invalid ticker");
    await expect(
      reg.connect(controller).setTicker(tokenId, "A_1")
    ).to.be.revertedWith("TickerRegistry: invalid ticker");
    await reg.connect(controller).setTicker(tokenId, "ching-axl-e1");
    const [pendingTicker] = await reg.getPending(tokenId);
    expect(pendingTicker).to.eq("CHING-AXL-E1");
  });

  it("enforces uniqueness with cooldown across changes", async function () {
    const { reg, controller } = await loadFixture(deployFixture);
    const tokenA = 1n;
    const tokenB = 2n;

    // shorten policies for test
    await reg.setRenamePolicy(1, 0); // cooldown 1s, timelock 0s

    // set for A
    await reg.connect(controller).setTicker(tokenA, "CHING-AXL-E1");
    await reg.connect(controller).finalizeTicker(tokenA);
    expect(await reg.getTicker(tokenA)).to.eq("CHING-AXL-E1");

    // cannot take same for B (reverts at setTicker)
    await expect(
      reg.connect(controller).setTicker(tokenB, "CHING-AXL-E1")
    ).to.be.revertedWith("TickerRegistry: ticker already taken");

    // change A to new ticker after cooldown
    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine", []);
    await reg.connect(controller).setTicker(tokenA, "CHING-AXL-E2");
    await reg.connect(controller).finalizeTicker(tokenA);
    expect(await reg.getTicker(tokenA)).to.eq("CHING-AXL-E2");

    // after A moved off E1, B can take E1
    await reg.connect(controller).setTicker(tokenB, "CHING-AXL-E1");
    await reg.connect(controller).finalizeTicker(tokenB);
    expect(await reg.getTicker(tokenB)).to.eq("CHING-AXL-E1");
  });

  it("enforces timelock before finalization", async function () {
    const { reg, controller } = await loadFixture(deployFixture);
    await reg.setRenamePolicy(0, 5); // no cooldown, timelock 5s
    const tokenId = 3n;
    await reg.connect(controller).setTicker(tokenId, "DELAY");
    await expect(reg.connect(controller).finalizeTicker(tokenId)).to.be.revertedWith("TickerRegistry: not ready");
    await ethers.provider.send("evm_increaseTime", [6]);
    await ethers.provider.send("evm_mine", []);
    await reg.connect(controller).finalizeTicker(tokenId);
    expect(await reg.getTicker(tokenId)).to.eq("DELAY");
  });

  it("rate limits changes per token and requires controller role", async function () {
    const { reg, controller, user } = await loadFixture(deployFixture);
    await reg.setRenamePolicy(10, 0); // long cooldown
    const tokenId = 7n;

    await expect(
      reg.connect(user).setTicker(tokenId, "AAA")
    ).to.be.revertedWithCustomError(reg, "AccessControlUnauthorizedAccount");

    await reg.connect(controller).setTicker(tokenId, "AAA");
    await reg.connect(controller).finalizeTicker(tokenId);

    // immediately setting again should fail due to cooldown
    await expect(
      reg.connect(controller).setTicker(tokenId, "AAB")
    ).to.be.revertedWith("TickerRegistry: cooldown");
  });

  it("clearTicker frees the name and emits events", async function () {
    const { reg, controller } = await loadFixture(deployFixture);
    await reg.setRenamePolicy(0, 0);
    const tokenId = 9n;
    await reg.connect(controller).setTicker(tokenId, "ABC");
    await expect(reg.connect(controller).finalizeTicker(tokenId))
      .to.emit(reg, "TickerSet");
    expect(await reg.getTicker(tokenId)).to.eq("ABC");

    await expect(reg.connect(controller).clearTicker(tokenId))
      .to.emit(reg, "TickerCleared");
    expect(await reg.getTicker(tokenId)).to.eq("");

    // can be re-taken by another token now
    const other = 10n;
    await reg.connect(controller).setTicker(other, "ABC");
    await reg.connect(controller).finalizeTicker(other);
    expect(await reg.getTicker(other)).to.eq("ABC");
  });
});


