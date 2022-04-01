// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IKuswapRouter02 {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract KCCSocialKuDogeSwap is Ownable {
    IKuswapRouter02 public _router = IKuswapRouter02(0xc5f442007e08e3b13C9f95fA22F2a2B9369d7C8C);
    IERC20 public _KuDoge = IERC20(0xe9B9106731D200fEc5335E1E01A26ec92624724B);
    IERC1155 public _KCCSocialNFT = IERC1155(0x618D116454A1AEdB0c6Cf2C714FB19c4c46bE0Bb);

    mapping(uint256 => bool) _isNFTIDPermittedToUseSwap;

    constructor() {
    }

    // Contract Control

    function SetRouter(address router) external onlyOwner
    {
        _router = IKuswapRouter02(router);
    }

    function SetKuDoge(address kudo) external onlyOwner
    {
        _KuDoge = IERC20(kudo);
    }

    function SetKCCSocialNFT(address nft) external onlyOwner
    {
        _KCCSocialNFT = IERC1155(nft);
    }

    function SetPermittedNFTs(uint256[] calldata nftIDs, bool permitted) external onlyOwner
    {
        for(uint256 i = 0; i < nftIDs.length; i++) {
            _isNFTIDPermittedToUseSwap[nftIDs[i]] = permitted;
        }
    }

    // Swap

    function swapExactETHForTokens(uint amountOutMin, uint256 usingNFTID) external payable returns (uint[] memory amounts)
    {
        //Require ownership of correct KCCSocial NFTs that enable the feeless KuDoge Swap
        require(_isNFTIDPermittedToUseSwap[usingNFTID], "This NFT does not unlock the feeless swap");
        require(_KCCSocialNFT.balanceOf(msg.sender, usingNFTID) > 0, "You do not own this NFT");

        address[] memory path = new address[](2);
        path[0] = _router.WETH();
        path[1] = address(_KuDoge);

        //This contract is feeless, so swapped tokens should be received by this and then forwarded
        amounts = _router.swapExactETHForTokens{value:msg.value}(amountOutMin, path, address(this), block.timestamp);

        _KuDoge.transfer(msg.sender, amounts[1]);
    }

    function getAmountsOut(uint amountIn) external view returns (uint[] memory amounts)
    {
        address[] memory path = new address[](2);
        path[0] = _router.WETH();
        path[1] = address(_KuDoge);

        amounts = _router.getAmountsOut(amountIn, path);
    }

    // Safety Fallbacks in case someone sends crypto to this contract

    function WithdrawKCS() external onlyOwner
    {
        Address.sendValue(payable(owner()), address(this).balance);
    }

    function WithdrawAnyToken(address token) external onlyOwner
    {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
