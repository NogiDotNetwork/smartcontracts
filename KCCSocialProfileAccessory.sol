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
        uint256 currentSupply;

        address[] accessoryOwners;
        mapping(address => uint256) ownerIndex;
    }

    struct UserNFTOwnership {
        uint256[] ownedNFTIDs;
    }

    KCCSocialTokenDistributor public _tokenDistributor;

    mapping(uint256 => OwnershipDetails) public _ownershipDetailsForNFTID;
    mapping(address => uint256) public _walletPurchaseCounter;
    mapping(address => UserNFTOwnership) private _userOwnedNFTs;
    mapping(address => mapping(uint256 => uint256)) private _userNFTOwnershipMapping;

    address private _signer = 0x4a6B3a5f12D71bbf7C1f7ce7A6231Db8A2656226;


    constructor() ERC1155("https://static.kcc.io/accessories/NFT_{id}") {

    }

    // Contract Control

    function setTokenDistributor(address distributorAddress) external onlyOwner
    {
        _tokenDistributor = KCCSocialTokenDistributor(distributorAddress);
    }

    function setSignerWallet(address signer) external onlyOwner
    {
        _signer = signer;
    }

    // Transfer

    function safeTransferFrom(address from,address to,uint256 id,uint256 amount,bytes calldata data) public override
    {
        bool previousOwnershipOfTo = balanceOf(to,id) > 0;

        super.safeTransferFrom(from, to, id, amount, data);

        _fixOwnershipData(from, to, id, previousOwnershipOfTo);
    }

    function safeBatchTransferFrom(address from, address to, uint256[] memory ids,uint256[] memory amounts,bytes memory data) public override
    {
        bool [] memory previousOwnershipOfTo = new bool[](ids.length);
        for(uint256 i = 0; i < ids.length; i++)
        {
            previousOwnershipOfTo[i] = balanceOf(to,ids[i]) > 0;
        }

        super.safeBatchTransferFrom(from, to, ids, amounts, data);

        for(uint256 i = 0; i < ids.length; i++)
        {
            _fixOwnershipData(from, to, ids[i], previousOwnershipOfTo[i]);
        }
    }

    // Purchase

    function purchaseAccessoryMulti(uint256[] calldata accessoryID, address paymentToken, uint256[] calldata amountPaying, bytes32 hash_, bytes memory signature, uint256 timestamp, uint256 purchaseCounter, uint256[] calldata supposedCurrentSupplies) external payable
    {
        require(accessoryID.length == amountPaying.length && supposedCurrentSupplies.length == amountPaying.length, "Uneven arrays!");

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

        require(hash_.toEthSignedMessageHash().recover(signature) == _signer, "Invalid Signature");
        require(hash_ == keccak256(abi.encodePacked(_msgSender(), purchaseCounter, accessoryID, timestamp, paymentToken, totalPayment, supposedCurrentSupplies)), "Invalid Hash");

        require(_walletPurchaseCounter[_msgSender()] == purchaseCounter, "This hash became invalid due to another transaction by you");

        _walletPurchaseCounter[_msgSender()] = _walletPurchaseCounter[_msgSender()] + 1;

        for(uint256 i = 0; i < accessoryID.length; i++) {
            _mintToTarget(accessoryID[i], _msgSender(), supposedCurrentSupplies[i]);
        }
    }

    function purchaseAccessory(uint256 accessoryID, address paymentToken, uint256 amountPaying, bytes32 hash_, bytes memory signature, uint256 timestamp, uint256 purchaseCounter, uint256 supposedCurrentSupply) external payable
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
        require(hash_ == keccak256(abi.encodePacked(_msgSender(), purchaseCounter, accessoryID, timestamp, paymentToken, amountPaying, supposedCurrentSupply)), "Invalid Hash");

        require(_walletPurchaseCounter[_msgSender()] == purchaseCounter, "This hash became invalid due to another transaction by you");

        _walletPurchaseCounter[_msgSender()] = _walletPurchaseCounter[_msgSender()] + 1;

        _mintToTarget(accessoryID, _msgSender(), supposedCurrentSupply);
    }

    // Safety Fallbacks in case someone sends crypto to this contract

    function withdrawKCS() external onlyOwner
    {
        Address.sendValue(payable(owner()), address(this).balance);
    }

    function withdrawAnyToken(address token) external onlyOwner
    {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    // External Info

    function accessoryOwnerCount(uint32 accessoryID) public view returns (uint256)
    {
        OwnershipDetails storage ownershipDetails = _ownershipDetailsForNFTID[accessoryID];

        return ownershipDetails.accessoryOwners.length;
    }

    function getBatchAccessoryOwners(uint32 accessoryID, uint256 start, uint256 end) public view returns (address[] memory accessoryOwners)
    {
        OwnershipDetails storage ownershipDetails = _ownershipDetailsForNFTID[accessoryID];

        address [] memory owners = new address[](end - start + 1);

        for (uint256 index = 0; index < owners.length; index++) {
            if(index + start >= ownershipDetails.accessoryOwners.length) {
                break;
            }
            owners[index] = ownershipDetails.accessoryOwners[index + start];
        }

        return owners;
    }

    function ownerUniqueTokenAmount(address owner) public view returns (uint256) {
        return _userOwnedNFTs[owner].ownedNFTIDs.length;
    }

    function ownerUniqueTokenIDs(address owner) external view returns (uint256[] memory ownedUniqueTokenIDs) {
        return _userOwnedNFTs[owner].ownedNFTIDs;
    }

    function ownerTokenBalanceByIndex(address owner, uint256 index) external view returns (uint256) {
        require(index < ownerUniqueTokenAmount(owner), "Enumerable: token index out of bounds for owner");
        return _userOwnedNFTs[owner].ownedNFTIDs[index];
    }

    function ownerTokenIDsAndBalances(address owner) external view returns (uint256[] memory ownedUniqueTokenIDs, uint256[] memory tokenBalances) {
        ownedUniqueTokenIDs = _userOwnedNFTs[owner].ownedNFTIDs;
        tokenBalances = new uint256[](ownedUniqueTokenIDs.length);

        for (uint256 index = 0; index < tokenBalances.length; index++) {
            tokenBalances[index] = balanceOf(owner, ownedUniqueTokenIDs[index]);
        }

        return (ownedUniqueTokenIDs, tokenBalances);

    }

    // Internal Utility

    function _mintToTarget(uint256 accessoryID, address targetUser, uint256 supposedCurrentSupply) internal
    {
        OwnershipDetails storage ownershipDetails = _ownershipDetailsForNFTID[accessoryID];

        require(supposedCurrentSupply == ownershipDetails.currentSupply, "Another transaction happened that made yours invalid, please try again.");

        ownershipDetails.currentSupply += 1;

        bool previousOwnershipOfTo = balanceOf(targetUser,accessoryID) > 0;

        _mint(targetUser, accessoryID, 1, "");

        if(!previousOwnershipOfTo) {
            ownershipDetails.ownerIndex[targetUser] = ownershipDetails.accessoryOwners.length;
            ownershipDetails.accessoryOwners.push(targetUser);

            _userNFTOwnershipMapping[targetUser][accessoryID] = _userOwnedNFTs[targetUser].ownedNFTIDs.length;
            _userOwnedNFTs[targetUser].ownedNFTIDs.push(accessoryID);
        }
    }

    function _fixOwnershipData(address from, address to, uint256 id, bool previousOwnershipOfTo) internal
    {
        OwnershipDetails storage ownershipDetails = _ownershipDetailsForNFTID[id];

        if(!previousOwnershipOfTo) {
            //If the receiver didn't previously have this NFT, add it to it's list of unique NFT IDs owned
            _userNFTOwnershipMapping[to][id] = _userOwnedNFTs[to].ownedNFTIDs.length;
            _userOwnedNFTs[to].ownedNFTIDs.push(id);
        }

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

            //If the sender doesn't own any amount of this NFT anymore, remove it from the sender's list of unique NFT IDs owned
            _userOwnedNFTs[from].ownedNFTIDs[_userNFTOwnershipMapping[from][id]] = _userOwnedNFTs[from].ownedNFTIDs[_userOwnedNFTs[from].ownedNFTIDs.length-1];
            _userOwnedNFTs[from].ownedNFTIDs.pop();
        }
        else if(!previousOwnershipOfTo) {
            //just new owner, so add to owner array
            ownershipDetails.ownerIndex[to] = ownershipDetails.accessoryOwners.length;
            ownershipDetails.accessoryOwners.push(to);
        }
    }
}
