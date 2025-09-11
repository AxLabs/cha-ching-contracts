import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ChaChing1155", function () {
  async function deployFixture() {
    const [deployer, alice, bob, carol] = await ethers.getSigners();
    const baseUri = "ipfs://";

    const ChaChing1155 = await ethers.getContractFactory("ChaChing1155");
    const cc = await ChaChing1155.deploy(baseUri, deployer.address);
    await cc.waitForDeployment();

    return { cc, deployer, alice, bob, carol, baseUri };
  }

  function toBytes32(hexOrString: string) {
    if (hexOrString.startsWith("0x")) return hexOrString as `0x${string}`;
    return ethers.id(hexOrString);
  }

  it("sets admin and metadata role for deployer", async function () {
    const { cc, deployer } = await loadFixture(deployFixture);
    const DEFAULT_ADMIN_ROLE = await cc.DEFAULT_ADMIN_ROLE();
    const METADATA_ROLE = await cc.METADATA_ROLE();
    expect(await cc.hasRole(DEFAULT_ADMIN_ROLE, deployer.address)).to.eq(true);
    expect(await cc.hasRole(METADATA_ROLE, deployer.address)).to.eq(true);
  });

  it("derives deterministic tokenId and equality with explicit chainId", async function () {
    const { cc } = await loadFixture(deployFixture);
    const net = await ethers.provider.getNetwork();
    const teamId = toBytes32("team-axlabs");
    const epochId = toBytes32("epoch-1");
    const derivedA = await cc["deriveEpochTokenId(bytes32,bytes32)"](teamId, epochId);
    const derivedB = await cc["deriveEpochTokenId(uint256,bytes32,bytes32)"](net.chainId, teamId, epochId);
    expect(derivedA).to.eq(derivedB);
  });

  it("creates epoch by derived method and exposes metadata via data URI", async function () {
    const { cc } = await loadFixture(deployFixture);
    const teamId = toBytes32("team-axlabs");
    const epochId = toBytes32("epoch-2");

    const meta = {
      name: "$CHING — AxLabs (Epoch 2)",
      symbol: "CHING-AXL",
      description: "Points for epoch 2",
      image: "ipfs://imageHash",
      teamSlug: "axlabs",
      attributesJSON: "[{\"trait_type\":\"epoch\",\"value\":2}]",
      exists: true,
    };

    const tokenId = await cc.createEpochDerived.staticCall(teamId, epochId, meta);
    await expect(cc.createEpochDerived(teamId, epochId, meta))
      .to.emit(cc, "EpochCreated")
      .withArgs(tokenId, meta.name, meta.symbol);

    const uri = await cc.uri(tokenId);
    expect(uri.startsWith("data:application/json;base64,")).to.eq(true);
    const payload = uri.split(",")[1];
    const json = JSON.parse(Buffer.from(payload, "base64").toString());
    expect(json.name).to.eq(meta.name);
    expect(json.symbol).to.eq(meta.symbol);
    expect(json.properties.team_slug).to.eq(meta.teamSlug);
  });

  it("falls back to base URI for non-existent id", async function () {
    const { cc, baseUri } = await loadFixture(deployFixture);
    const randomId = 123456789n;
    expect(await cc.uri(randomId)).to.eq(baseUri);
  });

  it("enforces name and symbol on creation/update and epoch existence", async function () {
    const { cc } = await loadFixture(deployFixture);
    const teamId = toBytes32("team-a");
    const epochId = toBytes32("epoch-a");
    const meta = {
      name: "A",
      symbol: "AA",
      description: "desc",
      image: "ipfs://img",
      teamSlug: "a",
      attributesJSON: "[]",
      exists: true,
    };
    const tokenId = await cc.createEpochDerived.staticCall(teamId, epochId, meta);
    await cc.createEpochDerived(teamId, epochId, meta);

    await expect(
      cc.createEpoch(tokenId, teamId, epochId, meta)
    ).to.be.revertedWith("ChaChing1155: epoch exists");

    await expect(
      cc.setEpochMetadata(tokenId, { ...meta, name: "" })
    ).to.be.revertedWith("ChaChing1155: name required");

    await expect(
      cc.setEpochMetadata(tokenId, { ...meta, symbol: "" })
    ).to.be.revertedWith("ChaChing1155: symbol required");

    await expect(
      cc.setEpochMetadata(999n, meta)
    ).to.be.revertedWith("ChaChing1155: epoch not found");
  });

  it("role-gates metadata, minting, and burning", async function () {
    const { cc, deployer, alice, bob } = await loadFixture(deployFixture);
    const teamId = toBytes32("team-rg");
    const epochId = toBytes32("epoch-rg");
    const meta = {
      name: "Role Gated",
      symbol: "RG",
      description: "",
      image: "",
      teamSlug: "rg",
      attributesJSON: "[]",
      exists: true,
    };
    const tokenId = await cc.createEpochDerived.staticCall(teamId, epochId, meta);
    await cc.createEpochDerived(teamId, epochId, meta);

    const MINTER_ROLE = await cc.MINTER_ROLE();
    const BURNER_ROLE = await cc.BURNER_ROLE();
    const METADATA_ROLE = await cc.METADATA_ROLE();

    await expect(cc.connect(alice).setURI("ipfs://new")).to.be.revertedWithCustomError(cc, "AccessControlUnauthorizedAccount");
    await cc.grantRole(METADATA_ROLE, alice.address);
    await cc.connect(alice).setURI("ipfs://new");

    await expect(cc.connect(alice).mint(bob.address, tokenId, 1, "0x"))
      .to.be.revertedWithCustomError(cc, "AccessControlUnauthorizedAccount");
    await cc.grantRole(MINTER_ROLE, alice.address);
    await cc.connect(alice).mint(bob.address, tokenId, 2, "0x");

    // supply tracking via ERC1155Supply
    const totalAfterMint = await cc["totalSupply(uint256)"](tokenId);
    expect(totalAfterMint).to.eq(2n);
    expect(await cc.exists(tokenId)).to.eq(true);

    await expect(cc.connect(bob).burn(bob.address, tokenId, 1))
      .to.be.revertedWithCustomError(cc, "AccessControlUnauthorizedAccount");
    await cc.grantRole(BURNER_ROLE, deployer.address);
    await cc.burn(bob.address, tokenId, 1);
    expect(await cc["totalSupply(uint256)"](tokenId)).to.eq(1n);
  });

  it("mintBatch checks all ids exist", async function () {
    const { cc, alice } = await loadFixture(deployFixture);
    const MINTER_ROLE = await cc.MINTER_ROLE();
    await cc.grantRole(MINTER_ROLE, alice.address);

    // create one valid id and one invalid
    const meta = {
      name: "B",
      symbol: "BB",
      description: "",
      image: "",
      teamSlug: "b",
      attributesJSON: "[]",
      exists: true,
    };
    const t1 = await cc.createEpochDerived.staticCall(toBytes32("t1"), toBytes32("e1"), meta);
    await cc.createEpochDerived(toBytes32("t1"), toBytes32("e1"), meta);
    const t2 = 999999n; // non-existent

    await expect(
      cc.connect(alice).mintBatch(alice.address, [t1, t2], [1, 1], "0x")
    ).to.be.revertedWith("ChaChing1155: epoch not found");
  });

  it("supports ERC1155 and AccessControl interfaces", async function () {
    const { cc } = await loadFixture(deployFixture);
    const ERC1155_INTERFACE_ID = "0xd9b67a26";
    const ACCESSCONTROL_INTERFACE_ID = "0x7965db0b";
    expect(await cc.supportsInterface(ERC1155_INTERFACE_ID)).to.eq(true);
    expect(await cc.supportsInterface(ACCESSCONTROL_INTERFACE_ID)).to.eq(true);
  });
});


