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
//import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import "hardhat/console.sol";

contract RewardTokensManager {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // State variables:

    IPoolManager public poolManager; // Manage pool
    IPositionManager public positionManager; // Manage liquidity positions
    PoolKey public pool;

    address public immutable pnpToken;
    address public immutable fnbToken;

    uint24 public constant FEE_TIER = 3000;
    uint24 public constant TICK_SPACING = 60;
    address public constant HOOKS = address(0);

    // Events:
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

    // Errors:
    error TickRangeDoesNotCoverAssignmentPrice();

    constructor(address _poolManager, address _positionManager, address _pnpToken, address _fnbToken) {
        poolManager = IPoolManager(_poolManager);
        positionManager = IPositionManager(_positionManager); // instantiated the PositionManager
        pnpToken = _pnpToken;
        fnbToken = _fnbToken;
    }

    /// @notice calculate the target tick for the reward tokens based on the token price ratio.
    /// @return targetTick The tick corresponding to the sqrt price ratio of the two reward tokens.
    function getTargetTick() public view returns (int24) {
        // FNBT = R0.10
        // PNPT = R0.01
        // notion is 1 FNBT ≡ 10 PNPT
        // price = currency0 / currency1 = 1.0001^tick
        // Therefore,target tick = log(price) / log(1.0001)

        (address currency0, ) = getCanonicalCurrencies();

        //uint160 targetSqrtPrice;

        if (currency0 == fnbToken) {
            // price = FNBT/PNPT = 0.1/0.01 = 10
            // target ticket = log(10) / log(1.0001) = 23027.0022
            // round down
            return int24(23027);
            //OR
            // sqrtPriceX96 = sqrt(10) * 2^96
            // = 250541448375047936451903530594
            //targetSqrtPrice = 250541448375047936451903530594;
            // return TickMath.getTickAtSqrtPrice(targetSqrtPrice)
        } else {
            // price = PNPT/FNBT = 0.01/0.1 = 0.1
            // target ticket = log(0.1) / log(1.0001) = -23027.0022
            // round down
            return int24(-23027);
            // sqrtPriceX96 = sqrt(0.1) * 2^96
            // = 25054144837504793683645932800
            //targetSqrtPrice = 25054144837504793683645932800;
            // return TickMath.getTickAtSqrtPrice(targetSqrtPrice)
        }
    }

    function getPoolId() public view returns (bytes32) {
        return PoolId.unwrap(pool.toId());
    }

    function getCanonicalCurrencies() public view returns (address currency0, address currency1) {
        if (uint160(pnpToken) < uint160(fnbToken)) {
            // pnpToken address numeric value is smaller
            return (pnpToken, fnbToken);
        } else {
            // fnbToken address numeric value is smaller
            return (fnbToken, pnpToken);
        }
    }

    function createdPools(bytes32 poolId) public view returns (bool) {
        // Check if there is a pool that matches the poolId given.
        if (PoolId.unwrap(pool.toId()) == poolId) {
            return true;
        } else {
            return false;
        }
    }

    // Only the owner can create a pool (access control).
    //public onlyOwner
    function createPool(uint160 sqrtPriceX96) public returns (bytes32 poolId) {
        //Initialize or register the pool through the v4 PoolManager flow
        // with fee tier 0.3% (e.g. 3000 where applicable), tick spacing 60,
        // canonical currency ordering, and hooks as above.
        // Ensure currencies are ordered
        (address currency0, address currency1) = getCanonicalCurrencies();

        // Create the pool
        pool = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: FEE_TIER, // fee in pips
            tickSpacing: int24(TICK_SPACING), // granularity of the pool
            hooks: IHooks(HOOKS)
        });

        // Intialise the pool with a starting price
        // startingPrice xpressed as sqrtPriceX96 [floor(sqrt(token1 / token0) * 2^96)]
        IPoolManager(poolManager).initialize(pool, sqrtPriceX96);
        poolId = PoolId.unwrap(pool.toId());

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

    function mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired, // maximum amounts of token0 caller is willing to transfer
        uint256 amount1Desired // maximum amounts of token1 caller is willing to transfer
    ) external returns (uint256 positionId, bytes32 poolId) {
        // Validate user inputs and tick constraints.
        require(amount0Desired > 0 && amount1Desired > 0, "Desired amounts must be greater than zero");
        require(tickLower < tickUpper, "tickLower must be smaller than tickUpper");

        // Ensure the chosen range includes the target tick for the tokens liquidity pool.
        if (tickLower > getTargetTick() || tickUpper < getTargetTick()) {
            revert TickRangeDoesNotCoverAssignmentPrice();
        }
        // Resolve and verify the liquidity pool.
        PoolId poolId = PoolId.wrap(getPoolId());
        require(createdPools(PoolId.unwrap(poolId)), "Pool has not been created");

        // Compute liquidity from desired token amounts at the current pool price. //CHECK
        // Use LiquidityAmounts.getLiquidityForAmounts method. sqrtPriceX96 can be obtained from the poolManager using poolManager.getSlot0(poolId)
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        require(sqrtPriceX96 != 0, "Pool has no price");

        // Use LiquidityAmounts.getLiquidityForAmounts method
        // Calculates the theoretical liquidity each token amount could provide and returns the minimum of the two
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, // current pool price
            TickMath.getSqrtPriceAtTick(tickLower), // square root price at the lower tick boundary
            TickMath.getSqrtPriceAtTick(tickUpper), // square root price at the upper tick boundary
            amount0Desired, // desired amount of currency0
            amount1Desired // desired amount of currency1
        );
        require(liquidity > 0, "No Liquidity");

        //Pull desired token amounts from owner into this manager.
        // Hint: Use IERC20.transferFrom(msg.sender, address(this), amount) for currency0 / currency1 when the corresponding desired amount is non-zero; the caller must approve your contract on both tokens first
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

        // approve `PositionManager` as a spender
        // IAllowanceTransfer(address(permit2Address)).approve(
        //     currency0,
        //     address(positionManager),
        //     uint160(amount0Desired),
        //     uint48(0)
        // );
        // IAllowanceTransfer(address(permit2Address)).approve(
        //     currency1,
        //     address(positionManager),
        //     uint160(amount1Desired),
        //     uint48(0)
        // );
        //Prepare PositionManager mint actions and execute modifyLiquidities.

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

        //uint256 nextIdBefore = positionManager.nextTokenId();

        // Mint the position and settle the pair with modifyLiquidities().
        positionManager.modifyLiquidities(abi.encode(actions, mintParams), block.timestamp + 60);
        uint256 positionId = positionManager.nextTokenId() - 1; // get the positionId of the newly minted position (the next token ID minus one)

        // Verify mint succeeded.
        require(positionId > 0, "Mint Unsuccessful");

        // Return any unspent token dust and emit assignment event.
        uint256 remainingAmount0 = IERC20(currency0).balanceOf(address(this));
        if (remainingAmount0 > 0) {
            IERC20(currency0).transfer(msg.sender, remainingAmount0);
        }
        uint256 remainingAmount1 = IERC20(currency1).balanceOf(address(this));
        if (remainingAmount1 > 0) {
            IERC20(currency1).transfer(msg.sender, remainingAmount1);
        }
        // Trigger event
        emit LiquidityMinted(getPoolId(), positionId, msg.sender, tickLower, tickUpper, liquidity);

        return (positionId, getPoolId());
    }
}
