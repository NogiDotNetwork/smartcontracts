// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


interface KCCSocialTokenDistributor
{
    function AddExternalTokenPayment(uint256 accessoryID, address token, uint256 amount) external;
    function AddExternalKCSPayment(uint256 accessoryID, uint256 amount) external payable;
}

contract KCCSocialProfileAccessory is ERC1155, Ownable {
    using ECDSA for bytes32;

    struct OwnershipDetails {
        uint32 maxSupply;
        uint32 currentSupply;

        address[] accessoryOwners;
        mapping(address => uint256) ownerIndex;
    }

    KCCSocialTokenDistributor public _tokenDistributor;

    mapping(uint256 => OwnershipDetails) _accessoryForID;

    address private _signer = 0x4a6B3a5f12D71bbf7C1f7ce7A6231Db8A2656226;


    constructor() ERC1155("https://static.kcc.io/accessories/NFT_{id}") {

    }

    // Contract Control

    function AddOrModifyAccessoryDetails(uint256 id, uint32 maxSupply) external onlyOwner
    {
        OwnershipDetails storage ownershipDetails = _accessoryForID[id];

        require(maxSupply >= ownershipDetails.currentSupply, "Currrent Supply exceeds max supply!");

        ownershipDetails.maxSupply = maxSupply;
    }

    function SetTokenDistributor(address distributorAddress) external onlyOwner
    {
        _tokenDistributor = KCCSocialTokenDistributor(distributorAddress);
    }

    // Purchase

    function PurchaseAccessoryMulti(uint32[] calldata accessoryID, address paymentToken, uint256[] calldata amountPaying, bytes32[] calldata hash_, bytes[] memory signature, uint256 timestamp, uint256[] calldata salt) external payable
    {
        require(accessoryID.length == amountPaying.length && amountPaying.length == hash_.length && hash_.length == signature.length && signature.length == salt.length, "Uneven arrays!");

        uint256 totalPayment = 0;

        for(uint256 i = 0; i < amountPaying.length; i++) {
            totalPayment += amountPaying[i];
        }

        if(paymentToken == address(0)) {
            require(msg.value >= totalPayment, "Purchase amount must suit the total accessories price");

            for(uint256 i = 0; i < amountPaying.length; i++) {
                _tokenDistributor.AddExternalKCSPayment{value:amountPaying[i]}(accessoryID[i], amountPaying[i]);
            }
        }
        else {
            IERC20(paymentToken).transferFrom(_msgSender(), address(_tokenDistributor), totalPayment);

            for(uint256 i = 0; i < amountPaying.length; i++) {
                _tokenDistributor.AddExternalTokenPayment(accessoryID[i], paymentToken, amountPaying[i]);
            }
        }

        require(block.timestamp < timestamp, "This sale signature has expired");

        for(uint256 i = 0; i < accessoryID.length; i++) {
            require(hash_[i].toEthSignedMessageHash().recover(signature[i]) == _signer, "Invalid Signature");
            require(hash_[i] == keccak256(abi.encodePacked(_msgSender(), salt[i], accessoryID[i], timestamp, paymentToken)), "Invalid Hash");

            _mintToTarget(accessoryID[i], _msgSender(), 1);
        }
    }

    function PurchaseAccessory(uint32 accessoryID, address paymentToken, uint256 amountPaying, bytes32 hash_, bytes memory signature, uint256 timestamp, uint256 salt) external payable
    {
        if(paymentToken == address(0)) {
            require(msg.value >= amountPaying, "Purchase amount must suit the accessory price");

            _tokenDistributor.AddExternalKCSPayment{value:msg.value}(accessoryID, msg.value);
        }
        else {
            IERC20(paymentToken).transferFrom(_msgSender(), address(_tokenDistributor), amountPaying);

            _tokenDistributor.AddExternalTokenPayment(accessoryID, paymentToken, amountPaying);
        }

        require(block.timestamp < timestamp, "This sale signature has expired");

        require(hash_.toEthSignedMessageHash().recover(signature) == _signer, "Invalid Signature");
        require(hash_ == keccak256(abi.encodePacked(_msgSender(), salt, accessoryID, timestamp, paymentToken)), "Invalid Hash");

        _mintToTarget(accessoryID, _msgSender(), 1);
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

    // External Info

    function AccessoryOwnerCount(uint32 accessoryID) public view returns (uint256)
    {
        OwnershipDetails storage ownershipDetails = _accessoryForID[accessoryID];

        return ownershipDetails.accessoryOwners.length;
    }

    function GetBatchAccessoryOwners(uint32 accessoryID, uint256 start, uint256 end) public view returns (address[] memory accessoryOwners)
    {
        OwnershipDetails storage ownershipDetails = _accessoryForID[accessoryID];

        address [] memory owners = new address[](end - start + 1);

        for (uint256 index = 0; index < owners.length; index++) {
            if(index + start >= ownershipDetails.accessoryOwners.length) {
                break;
            }
            owners[index] = ownershipDetails.accessoryOwners[index + start];
        }

        return owners;
    }

    // Internal Utility

    function _mintToTarget(uint32 accessoryID, address targetUser, uint32 amount) internal
    {
        OwnershipDetails storage ownershipDetails = _accessoryForID[accessoryID];

        if(ownershipDetails.maxSupply > 0) require(ownershipDetails.currentSupply + amount <= ownershipDetails.maxSupply, "Purchase exceeds maximum supply!");

        ownershipDetails.currentSupply += amount;

        bool previousOwnershipOfTo = balanceOf(targetUser,accessoryID) > 0;

        _mint(targetUser, accessoryID, amount, "");

        if(!previousOwnershipOfTo) {
            ownershipDetails.ownerIndex[targetUser] = ownershipDetails.accessoryOwners.length;
            ownershipDetails.accessoryOwners.push(targetUser);
        }
    }

    function _fixOwnershipData(address from, address to, uint256 id, bool previousOwnershipOfTo) internal
    {
        OwnershipDetails storage ownershipDetails = _accessoryForID[id];

        if(balanceOf(from,id) == 0)    {
            if(!previousOwnershipOfTo) {
                //the original owner doesnt have it anymore, so we override his ownership to the new owner
                ownershipDetails.accessoryOwners[ownershipDetails.ownerIndex[from]] = to;
                ownershipDetails.ownerIndex[to] = ownershipDetails.ownerIndex[from];
            }
            else {
                //new owner already had this accessory, so just remove old owner from owner array
                ownershipDetails.accessoryOwners[ownershipDetails.ownerIndex[from]] = ownershipDetails.accessoryOwners[ownershipDetails.accessoryOwners.length - 1];
                ownershipDetails.accessoryOwners.pop();
            }
        }
        else if(!previousOwnershipOfTo) {
            //just new owner, so add to owner array
            ownershipDetails.ownerIndex[to] = ownershipDetails.accessoryOwners.length;
            ownershipDetails.accessoryOwners.push(to);
        }
    }
}
