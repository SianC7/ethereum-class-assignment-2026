// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2; //Do not change the solidity version as it negatively impacts submission grading

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; //import the dependencies from OpenZeppelin

// FNBToken extends the ERC20 contract
contract FNBToken is ERC20 {
    // initialise ERC20 inherited code. ERC20(token name, symbol)
    constructor(uint256 totalFNBSupply) ERC20("FNB Token", "FNBT") {
        // mint the initial supply of FNB tokens
        _mint(msg.sender, totalFNBSupply); // deploy fnb token with a 1M supply and 18 decimals
    }
}
