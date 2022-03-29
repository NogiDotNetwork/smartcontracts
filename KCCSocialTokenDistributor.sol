// SPDX-License-Identifier: MIT
// created by: @superflatproportions | t.me/superflatproportions
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";


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

    uint256[] _nftShareIDs;
    uint256 _totalNFTOwnerShare;
    mapping(uint256 => uint256) _nftOwnerShares;
    mapping(address => uint256) _nftOwnerTotalUnclaimedTokens;
    mapping(uint256 => mapping(address => uint256)) _nftOwnerClaimedTokens;
    mapping(uint256 => mapping(address => uint256)) _nftOwnerUnclaimedTokens;

    address[] _supportedTokens;
    mapping(address => bool) _isTokenSupported;

    IERC1155 public _KCCSocialNFT;

    constructor() {
        _supportedTokens.push(address(0));
    }

    // Contract Control

    function SetKCCSocialNFT(address nft) external onlyOwner
    {
        _KCCSocialNFT = IERC1155(nft);
    }

    function AdjustUserGlobalShare(address user, uint256 share) external onlyOwner
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

    function AddNFTShareHolderIDs(uint256[] calldata nftIDs, uint256 share) external onlyOwner
    {
        UpdateNFTOwnerUnclaimedTokens();

        _totalNFTOwnerShare += share * nftIDs.length;
        for(uint256 i = 0; i < nftIDs.length; i++) {
            _nftShareIDs.push(nftIDs[i]);
            _nftOwnerShares[nftIDs[i]] = share;
        }
    }

    // Add Payment (In)

    function AddExternalTokenPayment(uint256 accessoryID, address token, uint256 amount) public
    {
        require(address(_KCCSocialNFT) == _msgSender(), "You are not allowed to do this.");

        if(!_isTokenSupported[token]) {
            _supportedTokens.push(token);
            _isTokenSupported[token] = true;
        }

        uint256 remainingTokens = amount;

        if(_totalNFTOwnerShare > 0) {
            uint256 nftOwnerShare = CalculateShare(remainingTokens, _totalNFTOwnerShare);
            _nftOwnerTotalUnclaimedTokens[token] += nftOwnerShare;
            remainingTokens -= nftOwnerShare;
        }

        PartnerShare storage parnterShare = _partnerShares[accessoryID];
        if(parnterShare.exists) {
            uint256 partnerShare = CalculateShare(remainingTokens, parnterShare.share);
            _partnerUnclaimedTokens[parnterShare.wallet][token] += partnerShare;
            _internalUnclaimedTokens[token] += remainingTokens - partnerShare;
        }
        else {
            _internalUnclaimedTokens[token] += remainingTokens;
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

    function TotalNFTUnclaimedIncome(uint256 nft, address token) internal view returns (uint256)
    {
        uint256 unclaimedNFTIncome = (_nftOwnerTotalUnclaimedTokens[token] * _nftOwnerShares[nft]) / _totalNFTOwnerShare;

        unclaimedNFTIncome -= _nftOwnerClaimedTokens[nft][token];
        unclaimedNFTIncome += _nftOwnerUnclaimedTokens[nft][token];
        return unclaimedNFTIncome;
    }

    function UpdateTotalUnclaimedTokens() internal
    {
        for(uint256 i = 0; i < _supportedTokens.length; i++) {
            address token = _supportedTokens[i];

            for(uint256 j = 0; j < _globalShareOwners.length; j++) {
                address user = _globalShareOwners[j];
                _unclaimedTokens[user][token] = TotalGlobalUnclaimedIncome(user, token);
                _claimedTokens[user][token] = 0;
            }

            _internalUnclaimedTokens[token] = 0;
        }
    }

    function UpdateNFTOwnerUnclaimedTokens() public onlyOwner
    {
        for(uint256 i = 0; i < _supportedTokens.length; i++) {
            address token = _supportedTokens[i];

            for(uint256 j = 0; j < _nftShareIDs.length; j++) {
                uint256 nftID = _nftShareIDs[j];
                _nftOwnerUnclaimedTokens[nftID][token] = TotalNFTUnclaimedIncome(nftID, token);
                _nftOwnerClaimedTokens[nftID][token] = 0;
            }

            _nftOwnerTotalUnclaimedTokens[token] = 0;
        }
    }

    function TotalUnclaimedIncome(address token, address user, uint256[] calldata ownedNFTs) public view returns (uint256)
    {
        uint256 globalClaimed = TotalGlobalUnclaimedIncome(user, token);
        uint256 parnerClaim = _partnerUnclaimedTokens[user][token];
        uint256 nftClaim = 0;

        for(uint256 i = 0; i < ownedNFTs.length; i++) {
            require(_KCCSocialNFT.balanceOf(user, ownedNFTs[i]) > 0, "You do not own these share holder NFTs");

            nftClaim += TotalNFTUnclaimedIncome(ownedNFTs[i], token);
        }

        uint256 totalUnclaimed = globalClaimed + nftClaim + parnerClaim;

        return totalUnclaimed;
    }

    // Withdraw

    function WithdrawToken(address token, address user, uint256[] calldata ownedNFTs) internal
    {
        uint256 unclaimed = TotalGlobalUnclaimedIncome(user, token);
        uint256 totalWithdraw = unclaimed + _partnerUnclaimedTokens[user][token];
        uint256 nftClaim = 0;

        for(uint256 i = 0; i < ownedNFTs.length; i++) {
            require(_KCCSocialNFT.balanceOf(user, ownedNFTs[i]) > 0, "You do not own these share holder NFTs");

            nftClaim += TotalNFTUnclaimedIncome(ownedNFTs[i], token);
            _nftOwnerUnclaimedTokens[ownedNFTs[i]][token] = 0;
            _nftOwnerClaimedTokens[ownedNFTs[i]][token] += nftClaim;
        }

        totalWithdraw += nftClaim;

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

    function WithdrawShares(uint256[] calldata ownedNFTs) external
    {
        for(uint256 i = 0; i < _supportedTokens.length; i++) {
            WithdrawToken(_supportedTokens[i], _msgSender(), ownedNFTs);
        }
    }
}
