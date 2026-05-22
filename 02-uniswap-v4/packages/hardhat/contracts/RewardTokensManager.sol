// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { LiquidityAmounts } from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

/// @notice A smart contract that creates a Uniswap v4 liquidity pool using PoolManager
/// @notice and also mints a concentrated liquidity position in the pool using PositionManager.
/// @notice RewardTokensManager inherits from Ownable.
contract RewardTokensManager is Ownable {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // State variables:
    IPoolManager public poolManager; // Manage pool
    IPositionManager public positionManager; // Manage liquidity positions
    PoolKey public pool; // Store liquidity pool

    // tokens
    address public immutable pnpToken; // Can't be changed after deployment
    address public immutable fnbToken; // Can't be changed after deployment

    // liquidity pool parameters
    uint24 public constant FEE_TIER = 3000;
    uint24 public constant TICK_SPACING = 60;
    address public constant HOOKS = address(0);

    // Events
    event PoolCreated(
        bytes32 poolId,
        address currency0,
        address currency1,
        uint256 fee,
        uint256 tickSpacing,
        address hooks,
        uint256 price
    );

    event LiquidityMinted(
        bytes32 poolId,
        uint256 positionId,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity
    );

    // Errors
    error TickRangeDoesNotCoverAssignmentPrice();

    // Constructor that initialises the contract with the addresses of the PoolManager, PositionManager, and reward tokens.
    constructor(
        address _poolManager,
        address _positionManager,
        address _pnpToken,
        address _fnbToken
    ) Ownable(msg.sender) {
        // call to the Ownable contract's constructor
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager); // instantiated the PositionManager
        pnpToken = _pnpToken;
        fnbToken = _fnbToken;
    }

    /// @notice Calculate the target tick for the reward tokens based on the token price ratio.
    /// @return targetTick - the tick corresponding to the sqrt price ratio of the two reward tokens.
    function getTargetTick() public view returns (int24) {
        // Pricing logic:
        // FNBT = R0.10
        // PNPT = R0.01
        // notion is 1 FNBT ≡ 10 PNPT
        // price = currency0 / currency1 = 1.0001^tick
        // Therefore, target tick = log(price) / log(1.0001)

        (address currency0, ) = getCanonicalCurrencies();
        int24 targetTick;
        //OR: uint160 targetSqrtPrice;

        if (currency0 == fnbToken) {
            // price = FNBT/PNPT = 0.1/0.01 = 10
            // target ticket = log(10) / log(1.0001) = 23027.0022
            // round down
            targetTick = int24(23027);
            return targetTick;
        } else {
            // price = PNPT/FNBT = 0.01/0.1 = 0.1
            // target ticket = log(0.1) / log(1.0001) = -23027.0022
            // round down
            targetTick = int24(-23027);
            return targetTick;
        }
    }

    /// @notice Allows the poolId to be read/ retrieved.
    /// @notice public and view method modifer so external callers can also (only) read the canonical currency order.
    /// @return  poolId - return the id of the liquidity pool converted into bytes32 format.
    function getPoolId() public view returns (bytes32) {
        return PoolId.unwrap(pool.toId());
    }

    /// @notice Allows the canonical order of the currency addresses to be read/retrieved.
    /// @notice public and view method modifer so external callers can also (only) read the canonical currency order.
    /// @return currency0 - The token/currency address with the smaller address value.
    /// @return currency1 - The token/currency address with the larger address value.
    function getCanonicalCurrencies() public view returns (address currency0, address currency1) {
        if (uint160(pnpToken) < uint160(fnbToken)) {
            // pnpToken address numeric value is smaller
            return (pnpToken, fnbToken);
        } else {
            // fnbToken address numeric value is smaller
            return (fnbToken, pnpToken);
        }
    }

    /// @notice Determines if the poolId given belongs to an existing liquidity pool.
    /// @param poolId The poolId in bytes32 to check for existence of the pool.
    /// @return poolExists indicating whether the given poolId matches an existing poolId of a created pool or not.
    function createdPools(bytes32 poolId) public view returns (bool) {
        bool poolExists = false;
        if (PoolId.unwrap(pool.toId()) == poolId) {
            poolExists = true;
            return poolExists;
        } else {
            poolExists = false;
            return poolExists;
        }
    }

    /// @notice Creates a Uniswap v4 liquidity pool and initialises it with a starting price.
    /// @notice external and onlyOwner method modifiers to restrict access to only the contract owner.
    /// @param sqrtPriceX96 - the initial price of the pool expressed as a square root price in Q96 format.
    /// @return poolId - the id of the created liquidity pool in bytes32 format.
    function createPool(uint160 sqrtPriceX96) external onlyOwner returns (bytes32 poolId) {
        // Get currencies in order
        (address currency0, address currency1) = getCanonicalCurrencies();

        // Create the pool
        pool = PoolKey({
            currency0: Currency.wrap(currency0), // Convert currency addresses to Currency type
            currency1: Currency.wrap(currency1),
            fee: FEE_TIER, // fee tier 0.3%
            tickSpacing: int24(TICK_SPACING), // tick spacing 60 for granularity of the pool
            hooks: IHooks(HOOKS) // hook with address(0) convertd to IHooks type
        });

        // Call poolManager and initialise the pool with a starting price
        poolManager.initialize(pool, sqrtPriceX96);

        // Get poolId
        poolId = getPoolId();

        // Trigger event
        emit PoolCreated(
            poolId,
            currency0,
            currency1,
            uint256(FEE_TIER), // cast to uint256
            uint256(TICK_SPACING), //cast to uint256
            HOOKS,
            uint256(sqrtPriceX96) // cast to uint256
        );

        return poolId;
    }

    /// @notice Mint a concentrated liquidity position in the created pool
    /// @notice external and onlyOwner method modifiers to restrict access to only the contract owner.
    /// @param tickLower - the lower tick boundary of the liquidity position.
    /// @param tickUpper - the upper tick boundary of the liquidity position.
    /// @param amount0Desired - the desired amount of token0 to deposit.
    /// @param amount1Desired - the desired amount of token1 to deposit.
    /// @return positionId - the id of the created liquidity position in uint256 format.
    /// @return poolId - the id of the created liquidity pool in bytes32 format.
    function mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired, // maximum amounts of token0 caller is willing to transfer
        uint256 amount1Desired // maximum amounts of token1 caller is willing to transfer
    ) external onlyOwner returns (uint256 positionId, bytes32 poolId) {
        // Validate user inputs and tick constraints.
        require(amount0Desired > 0 && amount1Desired > 0, "Desired amounts must be greater than zero");
        require(tickLower < tickUpper, "tickLower must be smaller than tickUpper");
        require(tickLower % int24(TICK_SPACING) == 0, "tickLower not aligned"); // Ensure ticks aligned to tick spacing (is a multiple of the spacing)
        require(tickUpper % int24(TICK_SPACING) == 0, "tickUpper not aligned");

        // Ensure the chosen range includes the target tick for the tokens liquidity pool.
        if (tickLower > getTargetTick() || tickUpper < getTargetTick()) {
            revert TickRangeDoesNotCoverAssignmentPrice();
        }
        // Resolve and verify the liquidity pool.
        poolId = getPoolId();
        require(createdPools(poolId), "Pool has not been created");

        // Compute liquidity from desired token amounts at the current pool price.
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(PoolId.wrap(poolId));
        require(sqrtPriceX96 != 0, "Pool has no price");

        // Calculate theoretical liquidity each token amount can provide and return the minimum liquidity value between the two tokens.
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, // current pool price
            TickMath.getSqrtPriceAtTick(tickLower), // square root price at the lower tick boundary
            TickMath.getSqrtPriceAtTick(tickUpper), // square root price at the upper tick boundary
            amount0Desired, // desired amount of currency0
            amount1Desired // desired amount of currency1
        );
        require(liquidity > 0, "No Liquidity");

        //Pull desired token amounts from owner into manager.
        (address currency0, address currency1) = getCanonicalCurrencies();

        if (amount0Desired > 0) {
            IERC20(currency0).transferFrom(msg.sender, address(this), amount0Desired);
        }
        if (amount1Desired > 0) {
            IERC20(currency1).transferFrom(msg.sender, address(this), amount1Desired);
        }

        //Approve Permit2 so PositionManager can settle pool deltas.
        (bool success, bytes memory data) = address(positionManager).call(abi.encodeWithSignature("permit2()"));
        require(success, "permit2 call failed");
        address permit2Address = abi.decode(data, (address));

        IERC20(currency0).approve(permit2Address, amount0Desired);
        IERC20(currency1).approve(permit2Address, amount1Desired);

        // Prepare PositionManager mint actions and execute modifyLiquidities.
        // Actions:
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), // creates a new liquidity position
            uint8(Actions.SETTLE_PAIR) // indicates tokens must be paid by the caller (createsthe position)
        );

        bytes[] memory mintParams = new bytes[](2);

        // Encode MINT_POSITION parameters:
        mintParams[0] = abi.encode(
            pool, // pool to mint in
            tickLower, // lower tick position bound
            tickUpper, // upper tick position bound
            liquidity, // amount of liquidity units to add
            amount0Desired, // Maximum amount of token0 to transfer
            amount1Desired, // Maximum amount of token1 to transfer
            msg.sender, // Who receives the liquidity position
            bytes("") // optional hook data
        );

        // Encode SETTLE_PAIR parameters (Encode mint operation):
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);

        // Mint the position and settle the pair with modifyLiquidities().
        positionManager.modifyLiquidities(abi.encode(actions, mintParams), block.timestamp + 60);
        uint256 positionId = positionManager.nextTokenId() - 1; // get the positionId of the newly minted position (the next token ID minus one)

        // Verify mint succeeded.
        require(positionId > 0, "Mint Unsuccessful");

        // Return any unspent token dust
        uint256 remainingAmount0 = IERC20(currency0).balanceOf(address(this));
        if (remainingAmount0 > 0) {
            IERC20(currency0).transfer(msg.sender, remainingAmount0);
        }
        uint256 remainingAmount1 = IERC20(currency1).balanceOf(address(this));
        if (remainingAmount1 > 0) {
            IERC20(currency1).transfer(msg.sender, remainingAmount1);
        }

        // Emit event
        emit LiquidityMinted(getPoolId(), positionId, msg.sender, tickLower, tickUpper, liquidity);

        return (positionId, getPoolId());
    }
}
