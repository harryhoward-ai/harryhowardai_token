// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/HarryHowardAI.sol";

contract DeployToken is Script {
    function run() external {
        // 1. 获取私钥 (稍后在 .env 中配置，这里通过 vm 读取)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 2. 开始广播交易 (之后的操作都会上链)
        vm.startBroadcast(deployerPrivateKey);

        // 3. 部署合约 (100万代币)
        //uint256 initialSupply = 1000000 * 10 ** 18;
        HarryHowardAI token = new HarryHowardAI();

        // 4. 结束广播
        vm.stopBroadcast();

        // 可以在终端打印地址
        console.log("Token deployed to:", address(token));
    }
}
