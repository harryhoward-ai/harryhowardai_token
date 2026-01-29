// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HourlySquadGame.sol";

contract DeploySquadGame is Script {
    function run() external {
        // 1. 获取配置
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymentToken = vm.envAddress("PAYMENT_TOKEN_ADDRESS");
        address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER");

        // 2. 开始广播
        vm.startBroadcast(deployerPrivateKey);

        address operator = vm.envOr("OPERATOR_ADDRESS", msg.sender);

        // 3. 部署合约
        HourlySquadGame game = new HourlySquadGame(
            paymentToken,
            trustedForwarder,
            operator
        );

        // 4. 结束广播
        vm.stopBroadcast();

        console.log("HourlySquadGame deployed to:", address(game));
    }
}
