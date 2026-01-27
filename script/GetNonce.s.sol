// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract GetNonce is Script {
    function run() external view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 nonce = vm.getNonce(deployer);

        console.log("Address:", deployer);
        console.log("Nonce:", nonce);
    }
}
