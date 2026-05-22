//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OrderBook {
    using SafeERC20 for IERC20;

    // State Variables: permanently store and maintain the contract's data on the blockchain
    struct Order { // Structure to represent an order
        address traderAddress; // address of the trader who placed the order
        uint256 initialAmount; // total initial order amount
        uint256 filledAmount; // how much of order has been filled so far
        uint256 price;
        bool active;
    }

    uint256 public orderIdCounter = 0; // Counter to assign unique IDs to orders

    mapping(uint256 => Order) public Orders; // Mapping to store orders by their ID

    address public immutable tokenA;
    address public immutable tokenB;

    // Events: logging and notifying off-chain applications that something has happened.
    event OrderPlaced(
        uint256 orderId,
        address trader,
        uint8 orderType, // 0 for buy, 1 for sell
        address tokenIn, // token address being requested
        address tokenOut, // token address being offered
        uint256 amount,
        uint256 price
    );

    event OrderMatched(uint256 buyOrderId, uint256 sellOrderId);

    event OrderFilled(uint256 orderId, uint256 filledAmount);
    event OrderPartiallyFilled(uint256 orderId, uint256 filledAmount);

    event OrderCanceled(uint256 orderId);

    // Custome Errors
    error InvalidAmount();
    error InvalidPrice();
    error PriceMismatch();
    error OrderNotFound();
    error InsufficientBalance();
    error UnauthorizedCancellation();

    // Constructor
    constructor(address _tokenA, address _tokenB) {
        tokenA = _tokenA; // What the buyer wants (PNPT)
        tokenB = _tokenB; // What the seller wants (FNBT)
    }

    // Functions
    /// @notice placeBuyOrder allows a user to place a buy order with the amount of tokenA they want to buy and how much in tokenB they are willing to pay.
    /// @param amount - amount of tokenA the buyer wants to buy.
    /// @param price - price the buyer is willing to pay for each unit of tokenA in terms of tokenB.
    /// @return orderId - the unique ID of the newly placed buy order.
    function placeBuyOrder(uint256 amount, uint256 price) external returns (uint256 orderId) {
        // Check price and amount are valid
        if (amount <= 0) revert InvalidAmount();
        if (price <= 0) revert InvalidPrice();

        // get order id from counter and increment counter after for next order
        orderId = orderIdCounter++;

        // Create state variable and add it to the Orders mapping:
        Orders[orderId] = Order({
            traderAddress: msg.sender, // sender of the order request
            initialAmount: amount, // The total amount of tokenA the buyer wants to buy (TRADE_AMOUNT)
            filledAmount: 0, // no part of the order is filled when the order is created
            price: price, // The price at which the buyer wants to buy the tokenA in terms of tokenB (PRICE)
            active: true // The order is active when it's placed
        });

        // Trigger event:
        emit OrderPlaced(
            orderId,
            msg.sender, // The address of the trader placing the order (sender of the transaction).
            0, // buy order
            tokenB, // address of tokenB that the buyer is selling for tokenA
            tokenA, // address of the tokenA the buyer wants
            amount,
            price
        );

        return orderId; // Return the order ID
    }

    /// @notice placeSellOrder allows a user to place a sell order with the amount of tokenA they want to sell and how much in tokenB they are willing to receive.
    /// @param amount - amount of tokenA the seller wants to sell.
    /// @param price - price the seller is willing to receive for each unit of tokenA in terms of tokenB.
    /// @return orderId - the unique ID of the newly placed sell order.
    function placeSellOrder(uint256 amount, uint256 price) external returns (uint256 orderId) {
        // Check price and amount are valid
        if (amount <= 0) revert InvalidAmount();
        if (price <= 0) revert InvalidPrice();

        // get order id from counter and increment counter after for next order
        orderId = orderIdCounter++;

        // Create order state variable and add it to the Orders mapping:
        Orders[orderId] = Order({
            traderAddress: msg.sender, // sender of the order request
            initialAmount: amount, // The total amount of tokenA the seller wants to sell (TRADE_AMOUNT)
            filledAmount: 0, // no part of the order is filled when the order is created
            price: price, // The price the seller wants to sell the tokenA at (PRICE)
            active: true // The order is active when it's placed.
        });

        // Trigger event:
        emit OrderPlaced(
            orderId,
            msg.sender, // The address of the trader placing the order (sender of the transaction).
            1, // sell order
            tokenA, // address of tokenA that the seller is selling for tokenB
            tokenB, // address of the tokenB, which the seller wants
            amount,
            price
        );

        return orderId; // Return the order ID
    }
    /// @notice Matching Engine to find buy and sell orders, check if they are compatible (buy price >= sell price), and execute the trade by transferring tokens.
    /// @param buyOrderId - the ID of the order the buyer has placed.
    /// @param sellOrderId - the ID of the order the seller has placed.
    function matchOrders(uint256 buyOrderId, uint256 sellOrderId) external {
        Order memory buyOrder = Orders[buyOrderId];
        Order memory sellOrder = Orders[sellOrderId];
        // If the orderIds exist and are active
        if (buyOrder.traderAddress == address(0) || sellOrder.traderAddress == address(0)) {
            revert OrderNotFound();
        }

        require(buyOrder.active, "Buy order is not active");
        require(sellOrder.active, "Sell order is not active");

        // Check asking price >= selling price
        if (buyOrder.price < sellOrder.price) {
            revert PriceMismatch();
        }

        // Get the maximum amount of tokenA that can be transfered between the orders
        uint256 transferAmount = 0;

        if ((buyOrder.initialAmount - buyOrder.filledAmount) < (sellOrder.initialAmount - sellOrder.filledAmount)) {
            transferAmount = buyOrder.initialAmount - buyOrder.filledAmount;
        } else {
            transferAmount = sellOrder.initialAmount - sellOrder.filledAmount;
        }

        // Check if tokens A and B can be transfered first.
        // allowance() to check if the user has approved the order book contract to transfer the tokens on their behalf
        // balanceOf() to check if a party has enough tokens to transfer.
        if (
            IERC20(tokenA).allowance(sellOrder.traderAddress, address(this)) < transferAmount ||
            IERC20(tokenA).balanceOf(sellOrder.traderAddress) < transferAmount
        ) {
            revert InsufficientBalance(); // Return error if the seller has not approved enough tokens for transfer
        }
        if (
            // token A = 2 token B
            IERC20(tokenB).allowance(buyOrder.traderAddress, address(this)) < transferAmount * sellOrder.price ||
            IERC20(tokenB).balanceOf(buyOrder.traderAddress) < transferAmount * sellOrder.price
        ) {
            revert InsufficientBalance(); // Return error if the buyer has not approved enough tokens for transfer
        }

        // Update fill amounts
        buyOrder.filledAmount = buyOrder.filledAmount + transferAmount;
        sellOrder.filledAmount = sellOrder.filledAmount + transferAmount;

        // Update status of orders if they are fully filled
        if (buyOrder.initialAmount == buyOrder.filledAmount) {
            emit OrderFilled(buyOrderId, buyOrder.filledAmount);
            buyOrder.active = false; // Order has been completed
        } else {
            emit OrderPartiallyFilled(buyOrderId, buyOrder.filledAmount);
        }

        if (sellOrder.initialAmount == sellOrder.filledAmount) {
            emit OrderFilled(sellOrderId, sellOrder.filledAmount);
            sellOrder.active = false; // Order has been completed
        } else {
            emit OrderPartiallyFilled(sellOrderId, sellOrder.filledAmount);
        }

        // Write updates back to mapping
        Orders[buyOrderId] = buyOrder;
        Orders[sellOrderId] = sellOrder;

        // Transfer the tokens
        // Seller sends tokenA (PNPT) to buyer, buyer sends tokenB (FNBT) to seller at the seller's price.
        IERC20(tokenA).safeTransferFrom(sellOrder.traderAddress, buyOrder.traderAddress, transferAmount); // Seller sends tokenA to buyer
        IERC20(tokenB).safeTransferFrom(
            buyOrder.traderAddress,
            sellOrder.traderAddress,
            transferAmount * sellOrder.price
        ); // Buyer sends tokenB to seller at the seller's price (1 token A = 2 token B)

        // Trigger event
        emit OrderMatched(buyOrderId, sellOrderId); //log the matched orders
    }

    /// @notice Cancel the order in the order book. Check if the cancellation is authorised.
    /// @param orderId - the ID of the order to be cancelled.
    function cancelOrder(uint256 orderId) external {
        Order memory thisOrder = Orders[orderId];
        if (thisOrder.active) {
            if (msg.sender != thisOrder.traderAddress) {
                revert UnauthorizedCancellation();
            } else {
                // Change the order status to inactive and prevent any further matching of the order.
                thisOrder.active = false;
                Orders[orderId] = thisOrder; // Write the update back to mapping
                // Trigger event:
                emit OrderCanceled(orderId);
            }
        }
    }

    /// @notice remaining shows the remaining amount of an order that is yet to be filled.
    /// @param orderId - the ID of the order to be checked.
    /// @return remainingAmount - the remaining amount of the order (initialAmount - filledAmount).
    function remaining(uint256 orderId) external view returns (uint256) {
        // show the remaining amount of the order that is yet to be forfilled (initialAmount - filledAmount).
        uint256 remainingAmount = 0;
        Order memory thisOrder = Orders[orderId]; // loads a copy of the order data based on orderId from the Orders mapping.

        if (thisOrder.traderAddress != address(0)) {
            // if the order exists:
            remainingAmount = thisOrder.initialAmount - thisOrder.filledAmount;
            require(remainingAmount >= 0, "Filled amount cannot exceed initial amount");
            return remainingAmount;
        } else {
            revert OrderNotFound(); // Return error if the order is not active
        }
    }

    /// @notice isOpen checks if an order is still active and has a remaining amount to be filled.
    /// @param orderId - the ID of the order to be checked.
    /// @return bool - true if the order is active and has remaining amount to be filled
    function isOpen(uint256 orderId) external view returns (bool) {
        Order memory thisOrder = Orders[orderId];
        if (thisOrder.active && (thisOrder.initialAmount - thisOrder.filledAmount) > 0) {
            return true; // Return true if the order exists and is active
        } else {
            return false; // Return false if the order is not active
        }
    }
}
