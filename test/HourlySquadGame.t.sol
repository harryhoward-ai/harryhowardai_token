// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HourlySquadGame.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20, ERC20Permit {
    constructor() ERC20("MockToken", "MTK") ERC20Permit("MockToken") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract PermitDebugTest is Test {
    HourlySquadGame public game;
    MockToken public token;

    uint256 internal userPrivateKey;
    address internal user;
    address internal relayer;

    // Permit TypeHash
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    function setUp() public {
        userPrivateKey = 0xA11CE;
        user = vm.addr(userPrivateKey);
        relayer = address(0xB0B);

        token = new MockToken();
        game = new HourlySquadGame(address(token), relayer); // trustedForwarder can be relayer or anything

        // Give user some tokens
        token.mint(user, 1000 * 10 ** 18);
    }

    function testPlaceBetWithPermit_Relayed() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;
        uint8 faction = 0;

        // 1. Prepare Permit Signature
        uint256 nonce = token.nonces(user);
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                user,
                address(game),
                amount,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // 2. Relayer calls the function
        // Switch to relayer
        vm.prank(relayer);

        // Before bet
        assertEq(token.balanceOf(user), 1000 * 10 ** 18);
        assertEq(token.balanceOf(address(game)), 0);

        // Call
        game.placeBetWithPermit(
            user, // bettor
            faction,
            amount,
            deadline,
            v,
            r,
            s
        );

        // 3. Verify
        assertEq(token.balanceOf(user), 900 * 10 ** 18);
        assertEq(token.balanceOf(address(game)), 100 * 10 ** 18);

        // Verify bet info
        uint256 roundId = game.getCurrentRoundId();
        // Since bets mapping is private-ish (public getter), let's check it
        (uint256 betAmount, uint8 betFaction, bool isClaimed) = game.bets(
            roundId,
            user
        );
        assertEq(betAmount, amount);
        assertEq(betFaction, faction);
        assertFalse(isClaimed);
    }
}
