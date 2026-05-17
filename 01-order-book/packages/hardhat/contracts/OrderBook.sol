//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

contract OrderBook {
    // State Variables: permanently store and maintain the contract's data on the blockchain
    struct Order { // Structure to represent an order
        address traderAddress; // address of the trader who placed the order
        uint256 initialAmount; // total initial order amount
        uint256 filledAmount; // how much of order has been filled so far
        uint256 price;
        bool active;
    }

    uint256 public orderIdCounter = 0; // Counter to assign unique IDs to orders

    mapping(uint256 => Order) public buyOrders; // Mapping to store buyorders (bids) by their ID
    mapping(uint256 => Order) public sellOrders;

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
        tokenA = _tokenA; // What the buyer wants
        tokenB = _tokenB; // What the seller wants
    }

    // Functions

    function placeBuyOrder(uint256 amount, uint256 price) external returns (uint256 orderId) {
        // Check price and amount are valid
        if (amount <= 0) revert InvalidAmount();
        if (price <= 0) revert InvalidPrice();

        if (orderIdCounter == 0) {
            orderId = orderIdCounter;
        } else {
            orderIdCounter += 1; // Increment the order ID counter to get a new unique order ID
            orderId = orderIdCounter; // Assign the new order ID to the variable to be
        }

        // Check if the buyer has enough tokens to buy before placing the order.

        // Create state variable and add it to the buyOrders mapping:
        buyOrders[orderId] = Order({
            traderAddress: msg.sender, // sender of the order request
            initialAmount: amount, // The total amount of tokens the buyer wants to buy
            filledAmount: 0, // no part of the order is filled when the order is created
            price: price, // The price at which the buyer wants to buy the tokens
            active: true // The order is active when it's placed
        });

        // Add to mapping:

        // Trigger event:
        emit OrderPlaced(
            orderId,
            msg.sender, // The address of the trader placing the order (sender of the transaction).
            0, // buy order
            tokenB, // address of the token buyer is selling
            tokenA, // address of the token the buyer wants
            amount,
            price
        );

        return orderId; // Return the order ID of the newly placed buy order.
    }

    function placeSellOrder(uint256 amount, uint256 price) external returns (uint256 orderId) {
        // Check price and amount are valid
        if (amount <= 0) revert InvalidAmount();
        if (price <= 0) revert InvalidPrice();

        // Check if the seller has enough tokens to sell before placing the order.

        // Create a new sell order with the specified amount and price, and return the order ID.
        orderIdCounter += 1; // Increment the order ID counter to get a new unique order ID
        orderId = orderIdCounter; // Assign the new order ID to the variable to be

        // Create order state variable and add it to the sellOrders mapping:
        sellOrders[orderId] = Order({
            traderAddress: msg.sender, // sender of the order request
            initialAmount: amount, // The total amount of tokens the seller wants to sell
            filledAmount: 0, // no part of the order is filled when the order is created
            price: price, // The price the seller wants to sell the tokens at
            active: true // The order is active when it's placed.
        });

        // Trigger event:
        emit OrderPlaced(
            orderId,
            msg.sender, // The address of the trader placing the order (sender of the transaction).
            1, // sell order
            tokenA, // address of the token the seller is selling
            tokenB, // address of the token the seller wants
            amount,
            price
        );

        return orderId; // Return the order ID of the newly placed sell order.
    }

    function matchOrders(uint256 buyOrderId, uint256 sellOrderId) external {
        // Matching Engine
        // Find the buy and sell orders by their IDs, check if they are compatible for a trade (buy price >= sell price), and execute the trade by transferring the appropriate amounts of tokens between the buyer and seller.

        // If the orderIds exist and are active
        if (buyOrders[buyOrderId].traderAddress == address(0) || sellOrders[sellOrderId].traderAddress == address(0)) {
            revert OrderNotFound();
        }
        Order memory buyOrder = buyOrders[buyOrderId];
        Order memory sellOrder = sellOrders[sellOrderId];

        // Check asking price >= selling price
        if (buyOrder.price < sellOrder.price) {
            revert PriceMismatch();
        }

        // Get the maximum amount of tokens that can be transfered between the orders
        // seller sets the minimum price
        uint256 transferAmount = 0;

        if ((buyOrder.initialAmount - buyOrder.filledAmount) < (sellOrder.initialAmount - sellOrder.filledAmount)) {
            transferAmount = buyOrder.initialAmount - buyOrder.filledAmount;
        } else {
            transferAmount = sellOrder.initialAmount - sellOrder.filledAmount;
        }

        // // Check if the parties can actually transfer the tokens before updating the order status and transferring the tokens.
        // // allowance() to check if the user has approved the order book contract to transfer the tokens on their behalf
        // // balanceOf() to check if a party has enough tokens to transfer.
        // if (
        //     IERC20(tokenA).allowance(sellOrder.traderAddress, address(this)) <= transferAmount ||
        //     IERC20(tokenA).balanceOf(sellOrder.traderAddress) <= transferAmount
        // ) {
        //     revert InsufficientBalance(); // Return error if the seller has not approved enough tokens for transfer
        // }
        // if (
        //     IERC20(tokenB).allowance(buyOrder.traderAddress, address(this)) <= transferAmount * sellOrder.price ||
        //     IERC20(tokenB).balanceOf(buyOrder.traderAddress) <= transferAmount * sellOrder.price
        // ) {
        //     revert InsufficientBalance(); // Return error if the buyer has not approved enough tokens for transfer
        // }

        // Update fill amounts
        buyOrder.filledAmount = buyOrder.filledAmount + transferAmount;
        sellOrder.filledAmount = sellOrder.filledAmount + transferAmount;

        // Update status of orders if they are fully filled
        if (buyOrder.initialAmount == buyOrder.filledAmount) {
            buyOrder.active = false; // Order has been completed
        }

        if (sellOrder.initialAmount == sellOrder.filledAmount) {
            sellOrder.active = false; // Order has been completed
        }

        // Write updates back to mapping
        buyOrders[buyOrderId] = buyOrder;
        sellOrders[sellOrderId] = sellOrder;

        // Actually send the tokens:
        // Seller sends tokenB (FNBT) to buyer, buyer sends tokenA (PNPT) to seller at the seller's price.
        IERC20(tokenA).safeTransferFrom(sellOrder.traderAddress, buyOrder.traderAddress, transferAmount); // Seller sends tokenA to buyer
        IERC20(tokenB).safeTransferFrom(
            buyOrder.traderAddress,
            sellOrder.traderAddress,
            transferAmount * sellOrder.price
        ); // Buyer sends tokenB to seller at the seller's price

        // Trigger event:
        emit OrderMatched(buyOrderId, sellOrderId); //log the matched orders
    }
    function cancelOrder(uint256 orderId) external {
        if (buyOrders[orderId].active) {
            Order memory buyOrder = buyOrders[orderId];
            if (msg.sender != buyOrder.traderAddress) {
                revert UnauthorizedCancellation();
            } else {
                // Change the order status to inactive and prevent any further matching of the order.
                buyOrder.active = false;
                buyOrders[orderId] = buyOrder;
                // Trigger event:
                emit OrderCanceled(orderId);
            }
        } else if (sellOrders[orderId].active) {
            Order memory sellOrder = sellOrders[orderId];
            if (msg.sender != sellOrder.traderAddress) {
                revert UnauthorizedCancellation();
            } else {
                sellOrder.active = false;
                sellOrders[orderId] = sellOrder;
                emit OrderCanceled(orderId);
            }
        }
    }

    function remaining(uint256 orderId) external view returns (uint256) {
        // show the remaining amount of the order that is yet to be forfilled (initialAmount - filledAmount).
        uint256 remainingAmount = 0;

        if (buyOrders[orderId].traderAddress != address(0)) {
            Order memory buyOrder = buyOrders[orderId];
            remainingAmount = buyOrder.initialAmount - buyOrder.filledAmount;
            return remainingAmount;
        } else if (sellOrders[orderId].traderAddress != address(0)) {
            Order memory sellOrder = sellOrders[orderId];
            remainingAmount = sellOrder.initialAmount - sellOrder.filledAmount;
            return remainingAmount;
        } else {
            revert OrderNotFound(); // Return false if the order is not active
        }
    }

    // Check if the order is still active and has remaining amount to be filled.
    function isOpen(uint256 orderId) external view returns (bool) {
        // Try to find the order in buyOrders mapping and check if it's active
        if (buyOrders[orderId].active) {
            return true; // Return true if the buy order exists and is active

            // Try to find the order in sellOrders mapping and check if it's active
        } else if (sellOrders[orderId].active) {
            return true; // Return true if the sell order exists and is active
        } else {
            return false; // Return false if the order is not active
        }
    }
}
