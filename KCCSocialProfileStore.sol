// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface KCCSocialProfileAccessory is IERC1155
{
    function GetAccessoryPrice(uint32 accessoryID) external view returns (uint256);
    function ExternalPurchase(uint32 accessoryID, address targetUser, bytes32 hash, bytes memory signature, uint256 nonce) external;
}
interface KCCSocialTokenDistributor
{
    function AddExternalTokenPayment(uint256 accessoryID, address token, uint256 amount) external;
    function AddExternalKCSPayment(uint256 accessoryID, uint256 amount) external payable;
}

contract KCCSocialProfileStore is Ownable {
    KCCSocialProfileAccessory public _profileNFT;
    KCCSocialTokenDistributor public _tokenDistributor;

    IERC20 public _KuDoge;
    IERC20 public _WKCS;
    address public _KuDoPair;


    constructor() {
        _KuDoge = IERC20(0xe9B9106731D200fEc5335E1E01A26ec92624724B); //Testnet: 0xe9B9106731D200fEc5335E1E01A26ec92624724B Mainnet: 0x6665D66aFA48F527d86623723342CfA258cB8666
        _WKCS = IERC20(0xB296bAb2ED122a85977423b602DdF3527582A3DA); //Testnet: 0xB296bAb2ED122a85977423b602DdF3527582A3DA Mainnet: 0x4446Fc4eb47f2f6586f9fAAb68B3498F86C07521
        _KuDoPair = 0xCD3bb313E2989a9Ec68ab4678F147bD8488957c6; //Tesnet: 0xCD3bb313E2989a9Ec68ab4678F147bD8488957c6 Mainnet: 0xd60acab9c0337e4fc257aeadaca69ac744fa2a5f
    }

    // Contract Control

    function SetProfileNFTAddress(address nftAddress) external onlyOwner
    {
        _profileNFT = KCCSocialProfileAccessory(nftAddress);
    }
    function SetTokenDistributor(address distributorAddress) external onlyOwner
    {
        _tokenDistributor = KCCSocialTokenDistributor(distributorAddress);
    }
    function SetPaymentContractsAndRouters(address kudo, address wkcs, address pair) external onlyOwner
    {
        _KuDoge = IERC20(kudo);
        _WKCS = IERC20(wkcs);
        _KuDoPair = pair;
    }

    // External Info

    function AccessoryPrice(uint32 accessoryID) public view returns (uint256 accessoryPrice, uint256 accessoryPriceInKuDo)
    {
        uint256 kudoPerKCS = _KuDoge.balanceOf(_KuDoPair) / _WKCS.balanceOf(_KuDoPair);

        accessoryPrice = _profileNFT.GetAccessoryPrice(accessoryID);
        accessoryPriceInKuDo = kudoPerKCS * accessoryPrice;
    }

    // Purchase

    function PurchaseAccessoryWithKCS(uint32 accessoryID, bytes32 hash, bytes memory signature, uint256 nonce) external payable
    {
        (uint256 accessoryPrice, ) = AccessoryPrice(accessoryID);

        require(msg.value >= accessoryPrice, "Purchase amount must suit the accessory price");

        _tokenDistributor.AddExternalKCSPayment{value:msg.value}(accessoryID, msg.value);

        _profileNFT.ExternalPurchase(accessoryID, msg.sender, hash, signature, nonce);
    }

    function PurchaseAccessoryWithKuDo(uint32 accessoryID, uint256 amountPaying, bytes32 hash, bytes memory signature, uint256 nonce) external payable
    {
        (, uint256 accessoryPriceInKuDo) = AccessoryPrice(accessoryID);

        if(amountPaying < accessoryPriceInKuDo) {
            require(accessoryPriceInKuDo - amountPaying < accessoryPriceInKuDo / 10, "KuDo price changed too much, and the sent amount is no longer sufficient as it exceeds the 10% slippage.");
        }

        _tokenDistributor.AddExternalTokenPayment(accessoryID, address(_KuDoge), amountPaying);

        _KuDoge.transferFrom(_msgSender(), address(_tokenDistributor), amountPaying);

        _profileNFT.ExternalPurchase(accessoryID, msg.sender, hash, signature, nonce);
    }

    // Safety Fallbacks in case someone sends crypto to this contract

    function KCSBalance() public view returns (uint256)
    {
        return address(this).balance;
    }

    function WithdrawAll() external onlyOwner
    {
        Address.sendValue(payable(owner()), address(this).balance);
        _KuDoge.transfer(owner(), _KuDoge.balanceOf(address(this)));
    }
}
