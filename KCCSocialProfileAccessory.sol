// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract KCCSocialProfileAccessory is ERC1155, Ownable {
  using ECDSA for bytes32;

  struct Accessory {
    bool exists;
    uint256 price;

    address[] accessoryOwners;
    mapping(address => uint256) ownerIndex;
  }

  mapping(address => bool) _addressAllowedToStartMint;
  mapping(uint256 => Accessory) _accessoryForID;

  address private _signer = 0x4a6B3a5f12D71bbf7C1f7ce7A6231Db8A2656226;
  mapping(uint256 => bool) internal _usedNonces;


  constructor() ERC1155("https://static.kcc.io/accessories/NFT_{id}") {

  }

  // Contract Control

  function ChangeMintPermit(address addressToModify, bool allowedState) external onlyOwner
  {
    _addressAllowedToStartMint[addressToModify] = allowedState;
  }

  function AddOrModifyPriceAccessory(uint256 id, uint256 price) external onlyOwner
  {
    Accessory storage accessory = _accessoryForID[id];
    accessory.price = price;
  }

  // Mint

  function ExternalPurchase(uint32 accessoryID, address targetUser, bytes32 hash, bytes memory signature, uint256 nonce) external
  {
    require(_addressAllowedToStartMint[_msgSender()], "You are not allowed to mint.");
    require(hash.toEthSignedMessageHash().recover(signature) == _signer, "Invalid Signature");
    require(!_usedNonces[nonce], "Nonce already used");
    require(hash == keccak256(abi.encodePacked(targetUser, nonce, accessoryID)), "Invalid Hash");

    _mintToTarget(accessoryID, targetUser, 1);

    _usedNonces[nonce] = true;
  }

  function PromoMint(uint32 accessoryID, uint32 amount) external onlyOwner
  {
    _mintToTarget(accessoryID, _msgSender(), amount);
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

  function GetAccessoryPrice(uint32 accessoryID) public view returns (uint256)
  {
    Accessory storage accessory = _accessoryForID[accessoryID];
    require(accessory.exists, "Accessory does not exist");
    return accessory.price;
  }


  function AccessoryOwnerCount(uint32 accessoryID) public view returns (uint256)
  {
    Accessory storage accessory = _accessoryForID[accessoryID];
    require(accessory.exists, "Accessory does not exist");

    return accessory.accessoryOwners.length;
  }

  function GetBatchAccessoryOwners(uint32 accessoryID, uint256 start, uint256 end) public view returns (address[] memory accessoryOwners)
  {
    Accessory storage accessory = _accessoryForID[accessoryID];
    require(accessory.exists, "Accessory does not exist");

    address [] memory owners = new address[](end - start + 1);

    for (uint256 index = 0; index < owners.length; index++) {
      if(index + start >= accessory.accessoryOwners.length) {
          break;
      }
      owners[index] = accessory.accessoryOwners[index + start];
    }

    return owners;
  }

  function KCSBalance() public view returns (uint256)
  {
    return address(this).balance;
  }

  // Internal Utility

  function _mintToTarget(uint32 accessoryID, address targetUser, uint32 amount) internal
  {
      Accessory storage accessory = _accessoryForID[accessoryID];
      require(accessory.exists, "Accessory does not exist");

      bool previousOwnershipOfTo = balanceOf(targetUser,accessoryID) > 0;

      _mint(targetUser, accessoryID, amount, "");

      if(!previousOwnershipOfTo) {
        accessory.ownerIndex[targetUser] = accessory.accessoryOwners.length;
        accessory.accessoryOwners.push(targetUser);
      }
  }

  function _fixOwnershipData(address from, address to, uint256 id, bool previousOwnershipOfTo) internal
  {
    Accessory storage accessory = _accessoryForID[id];

    require(accessory.exists, "Accessory does not exist");

    if(balanceOf(from,id) == 0)  {
      if(!previousOwnershipOfTo) {
        //the original owner doesnt have it anymore, so we override his ownership to the new owner
        accessory.accessoryOwners[accessory.ownerIndex[from]] = to;
        accessory.ownerIndex[to] = accessory.ownerIndex[from];
      }
      else {
        //new owner already had accessory, so just remove old owner from owner array
        accessory.accessoryOwners[accessory.ownerIndex[from]] = accessory.accessoryOwners[accessory.accessoryOwners.length - 1];
        accessory.accessoryOwners.pop();
      }
    }
    else if(!previousOwnershipOfTo) {
      //just new owner, so add to owner array
      accessory.ownerIndex[to] = accessory.accessoryOwners.length;
      accessory.accessoryOwners.push(to);
    }
  }
}
