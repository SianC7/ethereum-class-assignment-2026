// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2; //Do not change the solidity version as it negatively impacts submission grading

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; //import the dependencies from OpenZeppelin

// PNPToken extends the ERC20 contract
contract PNPToken is ERC20 {
    // initialise ERC20 inherited code. ERC20(token name, symbol)
    constructor(uint256 totalPNPSupply) ERC20("PNP Token", "PNPT") {
        // mint the initial supply of PNP tokens
        _mint(msg.sender, totalPNPSupply); // deploy pnp token with a 1M supply and 18 decimals
    }
}
