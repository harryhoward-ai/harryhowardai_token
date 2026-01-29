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
        game = new HourlySquadGame(address(token), relayer, user); // trustedForwarder can be relayer or anything, operator is user

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

    function testDistributeRewards_Operator() public {
        address operator = address(0xCAFE);

        // 1. Set Operator
        game.setOperator(operator);
        assertEq(game.operator(), operator);

        // 2. Mock a round and bet (simplified flow)
        uint256[] memory roundIds = new uint256[](0);

        // Call as Operator
        vm.prank(operator);
        game.distributeRewards(user, roundIds); // Should succeed (empty loop)

        // Call as Random user
        vm.prank(address(0xDEAD));
        vm.expectRevert("Unauthorized");
        game.distributeRewards(user, roundIds);
    }

    function testSetOperator_OnlyOwner() public {
        address newOp = address(0xABCD);

        // Prank as non-owner (user is the operator initially in setUp, but not owner. Owner is test contract)
        // Wait, in setUp: game = new ... (this test contract is the owner)
        // Check owner
        assertEq(game.owner(), address(this));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        game.setOperator(newOp);

        // Call as owner
        game.setOperator(newOp);
        assertEq(game.operator(), newOp);
    }

    function testDistributeRewards_TrustedForwarder() public {
        // Relayer is set as TrustedForwarder in constructor
        vm.prank(relayer);
        uint256[] memory roundIds = new uint256[](0);
        game.distributeRewards(user, roundIds); // Should succeed
    }
}
