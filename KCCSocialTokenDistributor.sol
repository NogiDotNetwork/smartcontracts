// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract KCCSocialTokenDistributor is Ownable {
    struct PartnerShare {
        bool exists;
        address wallet;
        uint256 share;
    }

    mapping(uint256 => PartnerShare) _partnerShares;
    mapping(address => mapping(address => uint256)) _partnerUnclaimedTokens;

    address[] _globalShareOwners;
    mapping(address => uint256) _globalShares;
    mapping(address => uint256) _internalUnclaimedTokens;
    mapping(address => mapping(address => uint256)) _claimedTokens;
    mapping(address => mapping(address => uint256)) _unclaimedTokens;

    address[] _permittedTokens;
    mapping(address => bool) _permittedStores;

    constructor() {
    }

    // Contract Control

    function AddPermittedToken(address token) external onlyOwner
    {
        for(uint256 i = 0; i < _permittedTokens.length; i++) {
            require(_permittedTokens[i] != token, "Token already added!");
        }

        _permittedTokens.push(token);
    }

    function ChangePermittedStore(address token, bool allowed) external onlyOwner
    {
        _permittedStores[token] = allowed;
    }

    function AdjustUserGlobalShare(address user, uint256 share) internal
    {
        UpdateTotalUnclaimedTokens();

        _globalShares[user] = share;

        bool isInGlobalArray = false;
        for(uint256 j = 0; j < _globalShareOwners.length; j++)  {
            if(user == _globalShareOwners[j])  {
                isInGlobalArray = true;

                if(share == 0) {
                    _globalShareOwners[j] = _globalShareOwners[_globalShareOwners.length - 1];
                    delete _globalShareOwners[_globalShareOwners.length - 1];
                    return;
                }
            }
        }
        if(!isInGlobalArray && share > 0) {
            _globalShareOwners.push(user);
        }
    }

    function AdjustPartnerShare(address partner, uint256 share, uint256[] calldata nftIDs) external onlyOwner
    {
        for(uint256 i = 0; i < nftIDs.length; i++) {
            uint256 accessoryID = nftIDs[i];
            PartnerShare storage parnterShare = _partnerShares[accessoryID];
            parnterShare.exists = share > 0;
            parnterShare.wallet = partner;
            parnterShare.share = share;
        }
    }

    // Add Payment (In)

    function AddExternalTokenPayment(uint256 accessoryID, address token, uint256 amount) public
    {
        require(_permittedStores[_msgSender()], "You are not allowed to do this.");

        PartnerShare storage parnterShare = _partnerShares[accessoryID];
        if(parnterShare.exists) {
            uint256 partnerShare = CalculateShare(amount, parnterShare.share);
            _partnerUnclaimedTokens[parnterShare.wallet][token] += partnerShare;
            _internalUnclaimedTokens[token] += amount - partnerShare;
        }
        else {
            _internalUnclaimedTokens[token] += amount;
        }
    }

    function AddExternalKCSPayment(uint256 accessoryID, uint256 amount) external payable
    {
        AddExternalTokenPayment(accessoryID, address(0), amount);
    }

    // Internal Utility

    function CalculateShare(uint256 amount, uint256 share) internal pure returns (uint256)
    {
        return amount * share / 10000;
    }

    function GetGlobalShareForUser(address user) internal view returns (uint256)
    {
        if(user == owner()) {
            uint256 totalShare = 10000;

            for(uint256 j = 0; j < _globalShareOwners.length; j++) {
                totalShare -= _globalShares[_globalShareOwners[j]];
            }

            return totalShare;
        }

        return _globalShares[user];
    }

    function TotalGlobalUnclaimedIncome(address user, address token) internal view returns (uint256)
    {
        uint256 globalShare = GetGlobalShareForUser(user);

        uint256 unclaimedTokens = _unclaimedTokens[user][token];
        unclaimedTokens += CalculateShare(_internalUnclaimedTokens[token] - _claimedTokens[user][token], globalShare);

        return unclaimedTokens;
    }

    function UpdateTotalUnclaimedTokens() internal
    {
        for(uint256 i = 0; i < _permittedTokens.length; i++) {
            address token = _permittedTokens[i];

            for(uint256 j = 0; j < _globalShareOwners.length; j++) {
                address user = _globalShareOwners[j];
                _unclaimedTokens[user][token] = TotalGlobalUnclaimedIncome(user, token);
            }

            _internalUnclaimedTokens[token] = 0;
        }
    }

    // Withdraw

    function WithdrawToken(address token, address user) internal
    {
        uint256 unclaimed = TotalGlobalUnclaimedIncome(user, token);
        uint256 totalWithdraw = unclaimed + _partnerUnclaimedTokens[user][token];

        _unclaimedTokens[user][token] = 0;
        _claimedTokens[user][token] += unclaimed;
        _partnerUnclaimedTokens[user][token] = 0;

        if(totalWithdraw > 0) {
            if(token == address(0)) {
                Address.sendValue(payable(user), totalWithdraw);
            }
            else {
                IERC20(token).transfer(user, totalWithdraw);
            }
        }
    }

    function WithdrawShares() external
    {
        WithdrawToken(address(0), _msgSender());

        for(uint256 i = 0; i < _permittedTokens.length; i++) {
            WithdrawToken(_permittedTokens[i], _msgSender());
        }
    }
}
