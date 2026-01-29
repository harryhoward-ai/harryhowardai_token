// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HourlySquadGame.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WithdrawFunds is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address gameAddress = vm.envAddress("SQUAD_GAME_ADDRESS");
        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        HourlySquadGame game = HourlySquadGame(gameAddress);

        uint256 balance = IERC20(paymentToken).balanceOf(gameAddress);
        console.log("Contract Balance:", balance);

        if (balance > 0) {
            game.withdrawFunds(paymentToken, balance);
            console.log("Withdrawn:", balance);
        } else {
            console.log("No funds to withdraw");
        }

        vm.stopBroadcast();
    }
}
