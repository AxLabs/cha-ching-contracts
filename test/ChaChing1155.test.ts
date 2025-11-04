import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("ChaChing1155", function () {
  async function deployFixture() {
    const [deployer, alice, bob, carol] = await ethers.getSigners();
    const baseUri = "ipfs://";

    const ChaChing1155 = await ethers.getContractFactory("ChaChing1155");
    const cc = await ChaChing1155.deploy(baseUri, deployer.address, "Cha-Ching Points", "CHING");
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

  it("sets contract name and symbol", async function () {
    const { cc } = await loadFixture(deployFixture);
    expect(await cc.name()).to.eq("Cha-Ching Points");
    expect(await cc.symbol()).to.eq("CHING");
  });

  it("creates token and exposes metadata via data URI", async function () {
    const { cc } = await loadFixture(deployFixture);
    const tokenId = 1n;

    const meta = {
      name: "$CHING — AxLabs (Epoch 2)",
      symbol: "CHING-AXL",
      description: "Points for epoch 2",
      image: "ipfs://imageHash",
      attributesJSON: "[{\"trait_type\":\"epoch\",\"value\":2}]",
    };

    await expect(cc.createToken(tokenId, meta))
      .to.emit(cc, "TokenCreated")
      .withArgs(tokenId, meta.name, meta.symbol, meta.description, meta.image);

    const uri = await cc.uri(tokenId);
    expect(uri.startsWith("data:application/json;base64,")).to.eq(true);
    const payload = uri.split(",")[1];
    const json = JSON.parse(Buffer.from(payload, "base64").toString());
    expect(json.name).to.eq(meta.name);
    expect(json.properties.symbol).to.eq(meta.symbol);
    expect(json.description).to.eq(meta.description);
  });

  it("falls back to base URI for non-existent id", async function () {
    const { cc, baseUri } = await loadFixture(deployFixture);
    const randomId = 123456789n;
    expect(await cc.uri(randomId)).to.eq(baseUri);
  });

  it("enforces name and symbol on creation/update and token existence", async function () {
    const { cc } = await loadFixture(deployFixture);
    const tokenId = 2n;
    const meta = {
      name: "A",
      symbol: "AA",
      description: "desc",
      image: "ipfs://img",
      attributesJSON: "[]",
    };
    await cc.createToken(tokenId, meta);

    await expect(
      cc.createToken(tokenId, meta)
    ).to.be.revertedWith("ChaChing1155: token exists");

    await expect(
      cc.setTokenMetadata(tokenId, { ...meta, name: "" })
    ).to.be.revertedWith("ChaChing1155: name required");

    await expect(
      cc.setTokenMetadata(tokenId, { ...meta, symbol: "" })
    ).to.be.revertedWith("ChaChing1155: symbol required");

    await expect(
      cc.setTokenMetadata(999n, meta)
    ).to.be.revertedWith("ChaChing1155: token not found");
  });

  it("role-gates metadata, minting, and burning", async function () {
    const { cc, deployer, alice, bob } = await loadFixture(deployFixture);
    const tokenId = 3n;
    const meta = {
      name: "Role Gated",
      symbol: "RG",
      description: "",
      image: "",
      attributesJSON: "[]",
    };
    await cc.createToken(tokenId, meta);

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
      attributesJSON: "[]",
    };
    const t1 = 4n;
    await cc.createToken(t1, meta);
    const t2 = 999999n; // non-existent

    await expect(
      cc.connect(alice).mintBatch(alice.address, [t1, t2], [1, 1], "0x")
    ).to.be.revertedWith("ChaChing1155: token not found");
  });

  it("supports token enumeration", async function () {
    const { cc } = await loadFixture(deployFixture);
    expect(await cc.totalTokenTypes()).to.eq(0n);

    const meta = {
      name: "Test Token",
      symbol: "TEST",
      description: "Test",
      image: "ipfs://test",
      attributesJSON: "[]",
    };

    await cc.createToken(1n, meta);
    expect(await cc.totalTokenTypes()).to.eq(1n);
    expect(await cc.tokenByIndex(0)).to.eq(1n);

    await cc.createToken(2n, meta);
    expect(await cc.totalTokenTypes()).to.eq(2n);
    
    const allIds = await cc.getAllTokenIds();
    expect(allIds.length).to.eq(2);
    expect(allIds[0]).to.eq(1n);
    expect(allIds[1]).to.eq(2n);
  });

  it("supports ERC1155 and AccessControl interfaces", async function () {
    const { cc } = await loadFixture(deployFixture);
    const ERC1155_INTERFACE_ID = "0xd9b67a26";
    const ACCESSCONTROL_INTERFACE_ID = "0x7965db0b";
    expect(await cc.supportsInterface(ERC1155_INTERFACE_ID)).to.eq(true);
    expect(await cc.supportsInterface(ACCESSCONTROL_INTERFACE_ID)).to.eq(true);
  });
});


