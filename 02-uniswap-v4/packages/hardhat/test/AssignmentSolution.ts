import { expect } from "chai";
import { Contract } from "ethers";
import { ethers } from "hardhat";
import { FNBToken, PNPToken, RewardTokensManager } from "../typechain-types";
import poolManagerArtifact from "@uniswap/v4-core/out/PoolManager.sol/PoolManager.json";
import positionManagerArtifact from "@uniswap/v4-periphery/foundry-out/PositionManager.sol/PositionManager.json";
import positionDescriptorArtifact from "@uniswap/v4-periphery/foundry-out/PositionDescriptor.sol/PositionDescriptor.json";

function artifactBytecode(artifact: { bytecode: string | { object: string } }): string {
  return typeof artifact.bytecode === "string" ? artifact.bytecode : artifact.bytecode.object;
}

describe("Uniswap v4 Assignment Solution", function () {
  const INITIAL_SUPPLY = ethers.parseUnits("1000000", 18);
  const SQRT_PRICE_X96 = 79228162514264337593543950336n; // 2^96 => price 1
  const MINT_AMOUNTS = ethers.parseEther("50000");

  let pnpToken: PNPToken;
  let fnbToken: FNBToken;
  let positionManager: Contract;
  let tokensManager: RewardTokensManager;

  beforeEach(async () => {
    const [deployer] = await ethers.getSigners();

    const pnpFactory = await ethers.getContractFactory("PNPToken");
    pnpToken = (await pnpFactory.deploy(INITIAL_SUPPLY)) as PNPToken;
    await pnpToken.waitForDeployment();

    const fnbFactory = await ethers.getContractFactory("FNBToken");
    fnbToken = (await fnbFactory.deploy(INITIAL_SUPPLY)) as FNBToken;
    await fnbToken.waitForDeployment();

    const poolManagerFactory = new ethers.ContractFactory(
      poolManagerArtifact.abi,
      poolManagerArtifact.bytecode.object,
      deployer,
    );
    const poolManagerDeployed = await poolManagerFactory.deploy(deployer.address);
    await poolManagerDeployed.waitForDeployment();
    const poolManagerAddress = await poolManagerDeployed.getAddress();

    const mockPermit2Factory = await ethers.getContractFactory("MockPermit2");
    const mockPermit2 = await mockPermit2Factory.deploy();
    await mockPermit2.waitForDeployment();

    const mockWethFactory = await ethers.getContractFactory("MockWETH9");
    const mockWeth = await mockWethFactory.deploy();
    await mockWeth.waitForDeployment();
    const mockWethAddress = await mockWeth.getAddress();

    const descBytecode = artifactBytecode(positionDescriptorArtifact as { bytecode: string | { object: string } });
    const positionDescriptorFactory = new ethers.ContractFactory(
      positionDescriptorArtifact.abi,
      descBytecode,
      deployer,
    );
    const positionDescriptor = await positionDescriptorFactory.deploy(
      poolManagerAddress,
      mockWethAddress,
      ethers.encodeBytes32String("ETH"),
    );
    await positionDescriptor.waitForDeployment();

    const pmBytecode = artifactBytecode(positionManagerArtifact as { bytecode: string | { object: string } });
    const positionManagerFactory = new ethers.ContractFactory(positionManagerArtifact.abi, pmBytecode, deployer);
    const positionManagerDeployed = await positionManagerFactory.deploy(
      poolManagerAddress,
      await mockPermit2.getAddress(),
      500_000n,
      await positionDescriptor.getAddress(),
      mockWethAddress,
    );
    await positionManagerDeployed.waitForDeployment();
    positionManager = new Contract(await positionManagerDeployed.getAddress(), positionManagerArtifact.abi, deployer);

    const tokensManagerFactory = await ethers.getContractFactory("RewardTokensManager");
    tokensManager = (await tokensManagerFactory.deploy(
      poolManagerAddress,
      await positionManagerDeployed.getAddress(),
      await pnpToken.getAddress(),
      await fnbToken.getAddress(),
    )) as RewardTokensManager;
    await tokensManager.waitForDeployment();
  });

  it("creates the pool using 0.3% fee, spacing 60, no hooks, and emits PoolCreated", async () => {
    const [owner] = await ethers.getSigners();
    const tx = await tokensManager.createPool(SQRT_PRICE_X96);

    const poolId = await tokensManager.getPoolId();
    const [currency0, currency1] = await tokensManager.getCanonicalCurrencies();

    await expect(tx)
      .to.emit(tokensManager, "PoolCreated")
      .withArgs(poolId, currency0, currency1, 3000, 60, ethers.ZeroAddress, SQRT_PRICE_X96);

    expect(await tokensManager.createdPools(poolId)).to.equal(true);
    expect(await tokensManager.FEE_TIER()).to.equal(3000);
    expect(await tokensManager.TICK_SPACING()).to.equal(60);
    expect(await tokensManager.HOOKS()).to.equal(ethers.ZeroAddress);
    expect(owner.address).to.not.equal(ethers.ZeroAddress);
  });

  it("mints liquidity via PositionManager and emits LiquidityMinted", async () => {
    const [owner] = await ethers.getSigners();
    await tokensManager.createPool(SQRT_PRICE_X96);

    const targetTick = await tokensManager.getTargetTick();
    const tickLower = targetTick - (targetTick % 60n) - 120n;
    const tickUpper = targetTick - (targetTick % 60n) + 120n;

    // approving the RewardTokensManager contract to spend the sender's PNP and FNB tokens
    await pnpToken.connect(owner).approve(await tokensManager.getAddress(), MINT_AMOUNTS);
    await fnbToken.connect(owner).approve(await tokensManager.getAddress(), MINT_AMOUNTS);

    const poolId = await tokensManager.getPoolId(); // get contract's poolId
    const tx = await tokensManager.mintLiquidity(Number(tickLower), Number(tickUpper), MINT_AMOUNTS, MINT_AMOUNTS); // mint liquidity through the manager
    const receipt = await tx.wait();
    const tokensManagerAddress = await tokensManager.getAddress();
    let positionId = 0n;
    let emittedLiquidity = 0n;
    for (const log of receipt!.logs) {
      if (log.address.toLowerCase() !== tokensManagerAddress.toLowerCase()) continue;
      try {
        const parsed = tokensManager.interface.parseLog({
          topics: log.topics as string[],
          data: log.data,
        });
        if (parsed?.name === "LiquidityMinted") {
          positionId = parsed.args.positionId as bigint;
          emittedLiquidity = parsed.args.liquidity as bigint;
          break;
        }
      } catch {
        /* not this contract's event shape */
      }
    }
    expect(positionId).to.be.gt(0n); // positionId should be non-zero
    expect(emittedLiquidity).to.be.gt(0n); // emitted liquidity should be non-zero

    await expect(tx)
      .to.emit(tokensManager, "LiquidityMinted")
      .withArgs(poolId, positionId, owner.address, Number(tickLower), Number(tickUpper), emittedLiquidity);

    const pmLiq = await positionManager.getPositionLiquidity(positionId);
    expect(pmLiq).to.equal(emittedLiquidity);
    expect(await positionManager.ownerOf(positionId)).to.equal(owner.address);
    expect(await positionManager.nextTokenId()).to.equal(positionId + 1n);
  });

  it("reverts if minted range does not cover assignment implied tick", async () => {
    await tokensManager.createPool(SQRT_PRICE_X96);
    const targetTick = await tokensManager.getTargetTick();

    const alignedBase = targetTick - (targetTick % 60n);
    const tickLower = alignedBase + 120n;
    const tickUpper = alignedBase + 240n;

    const [owner] = await ethers.getSigners();
    await pnpToken.connect(owner).approve(await tokensManager.getAddress(), MINT_AMOUNTS);
    await fnbToken.connect(owner).approve(await tokensManager.getAddress(), MINT_AMOUNTS);

    await expect(
      tokensManager.mintLiquidity(Number(tickLower), Number(tickUpper), MINT_AMOUNTS, MINT_AMOUNTS),
    ).to.be.revertedWithCustomError(tokensManager, "TickRangeDoesNotCoverAssignmentPrice");
  });
});
