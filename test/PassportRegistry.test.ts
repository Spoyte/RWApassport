import { expect } from "chai";
import hre from "hardhat";

describe("PassportRegistry", function () {
  let passportRegistry: any;
  let owner: any;
  let issuer: any;
  let user: any;

  beforeEach(async function () {
    [owner, issuer, user] = await hre.ethers.getSigners();

    const PassportRegistry = await hre.ethers.getContractFactory("PassportRegistry");
    passportRegistry = await PassportRegistry.deploy(
      hre.ethers.ZeroAddress, // No price feed for testing
      owner.address
    );
    await passportRegistry.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await passportRegistry.owner()).to.equal(owner.address);
    });

    it("Should authorize owner as issuer", async function () {
      expect(await passportRegistry.isAuthorizedIssuer(owner.address)).to.be.true;
    });
  });

  describe("Issuer Management", function () {
    it("Should allow owner to add authorized issuer", async function () {
      await passportRegistry.addAuthorizedIssuer(issuer.address);
      expect(await passportRegistry.isAuthorizedIssuer(issuer.address)).to.be.true;
    });

    it("Should allow owner to remove authorized issuer", async function () {
      await passportRegistry.addAuthorizedIssuer(issuer.address);
      await passportRegistry.removeAuthorizedIssuer(issuer.address);
      expect(await passportRegistry.isAuthorizedIssuer(issuer.address)).to.be.false;
    });

    it("Should not allow non-owner to add issuer", async function () {
      await expect(
        passportRegistry.connect(user).addAuthorizedIssuer(issuer.address)
      ).to.be.revertedWithCustomError(passportRegistry, "OwnableUnauthorizedAccount");
    });
  });

  describe("Passport Creation", function () {
    beforeEach(async function () {
      await passportRegistry.addAuthorizedIssuer(issuer.address);
    });

    it("Should create a passport successfully", async function () {
      const assetType = "art";
      const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test metadata"));
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await expect(
        passportRegistry.connect(issuer).createPassport(
          assetType,
          metadataHash,
          metadata,
          proofs
        )
      ).to.emit(passportRegistry, "PassportCreated")
        .withArgs(0, issuer.address, assetType, metadataHash);

      const passport = await passportRegistry.getPassport(0);
      expect(passport.assetType).to.equal(assetType);
      expect(passport.metadataHash).to.equal(metadataHash);
      expect(passport.owner).to.equal(issuer.address);
      expect(passport.issuer).to.equal(issuer.address);
      expect(passport.isActive).to.be.true;
    });

    it("Should not allow unauthorized issuer to create passport", async function () {
      const assetType = "art";
      const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test metadata"));
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await expect(
        passportRegistry.connect(user).createPassport(
          assetType,
          metadataHash,
          metadata,
          proofs
        )
      ).to.be.revertedWith("Unauthorized issuer");
    });

    it("Should not create passport with empty asset type", async function () {
      const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test metadata"));
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await expect(
        passportRegistry.connect(issuer).createPassport(
          "",
          metadataHash,
          metadata,
          proofs
        )
      ).to.be.revertedWith("Asset type cannot be empty");
    });

    it("Should not create passport with zero metadata hash", async function () {
      const assetType = "art";
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await expect(
        passportRegistry.connect(issuer).createPassport(
          assetType,
          hre.ethers.ZeroHash,
          metadata,
          proofs
        )
      ).to.be.revertedWith("Invalid metadata hash");
    });
  });

  describe("Passport Verification", function () {
    let tokenId: number;

    beforeEach(async function () {
      await passportRegistry.addAuthorizedIssuer(issuer.address);
      
      const assetType = "art";
      const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test metadata"));
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await passportRegistry.connect(issuer).createPassport(
        assetType,
        metadataHash,
        metadata,
        proofs
      );
      tokenId = 0;
    });

    it("Should verify passport successfully", async function () {
      const newProofs = [
        hre.ethers.toUtf8Bytes("proof1"),
        hre.ethers.toUtf8Bytes("proof2"),
        hre.ethers.toUtf8Bytes("proof3")
      ];

      await expect(
        passportRegistry.connect(user).verifyPassport(tokenId, newProofs)
      ).to.emit(passportRegistry, "PassportVerified");

      const passport = await passportRegistry.getPassport(tokenId);
      expect(passport.verificationLevel).to.equal(2); // PREMIUM (3 proofs)
    });

    it("Should update verification level based on proof count", async function () {
      // Test ENHANCED level (2 proofs)
      const enhancedProofs = [
        hre.ethers.toUtf8Bytes("proof1"),
        hre.ethers.toUtf8Bytes("proof2")
      ];

      await passportRegistry.connect(user).verifyPassport(tokenId, enhancedProofs);
      let passport = await passportRegistry.getPassport(tokenId);
      expect(passport.verificationLevel).to.equal(1); // ENHANCED

      // Test BASIC level (1 proof)
      const basicProofs = [hre.ethers.toUtf8Bytes("proof1")];
      await passportRegistry.connect(user).verifyPassport(tokenId, basicProofs);
      passport = await passportRegistry.getPassport(tokenId);
      expect(passport.verificationLevel).to.equal(0); // BASIC
    });
  });

  describe("View Functions", function () {
    it("Should return total passports count", async function () {
      expect(await passportRegistry.getTotalPassports()).to.equal(0);
      
      await passportRegistry.addAuthorizedIssuer(issuer.address);
      const assetType = "art";
      const metadataHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test metadata"));
      const metadata = {
        title: "Test Art",
        description: "Test Description",
        category: "Digital Art",
        certifications: ["Test Cert"],
        attestationHashes: [hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"))]
      };
      const proofs = [hre.ethers.toUtf8Bytes("test proof")];

      await passportRegistry.connect(issuer).createPassport(
        assetType,
        metadataHash,
        metadata,
        proofs
      );

      expect(await passportRegistry.getTotalPassports()).to.equal(1);
    });

    it("Should return verified data hash status", async function () {
      const testHash = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test"));
      expect(await passportRegistry.isVerifiedDataHash(testHash)).to.be.false;
    });
  });
}); 