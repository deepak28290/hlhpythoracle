// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FundingOracle is Ownable, Pausable, ReentrancyGuard {
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MAX_FUNDING_RATE = 0.01e18; // 1% max funding rate
    uint256 public constant MIN_UPDATE_INTERVAL = 8 hours;
    
    uint256 public currentPrice;
    uint256 public lastUpdateTime;
    uint256 public totalFundingCaptured;
    
    mapping(address => bool) public authorizedUpdaters;
    
    struct FundingUpdate {
        uint256 timestamp;
        int256 fundingRate;
        uint256 oldPrice;
        uint256 newPrice;
    }
    
    FundingUpdate[] public fundingHistory;
    
    event PriceUpdated(
        uint256 indexed timestamp,
        int256 fundingRate,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 totalFundingCaptured
    );
    
    event UpdaterAuthorized(address indexed updater);
    event UpdaterRevoked(address indexed updater);
    
    modifier onlyAuthorizedUpdater() {
        require(authorizedUpdaters[msg.sender] || msg.sender == owner(), "Not authorized updater");
        _;
    }
    
    modifier validUpdateInterval() {
        require(
            block.timestamp >= lastUpdateTime + MIN_UPDATE_INTERVAL,
            "Update interval not met"
        );
        _;
    }
    
    constructor() Ownable(msg.sender) {
        currentPrice = PRECISION; // Start at 1.000
        lastUpdateTime = block.timestamp;
        totalFundingCaptured = 0;
        
        // Owner is initially authorized
        authorizedUpdaters[msg.sender] = true;
        
        // Record initial state
        fundingHistory.push(FundingUpdate({
            timestamp: block.timestamp,
            fundingRate: 0,
            oldPrice: PRECISION,
            newPrice: PRECISION
        }));
    }
    
    function updatePrice(int256 fundingRate) 
        external 
        onlyAuthorizedUpdater 
        whenNotPaused 
        validUpdateInterval
        nonReentrant 
    {
        require(fundingRate >= -int256(MAX_FUNDING_RATE), "Funding rate too negative");
        require(fundingRate <= int256(MAX_FUNDING_RATE), "Funding rate too positive");
        
        uint256 oldPrice = currentPrice;
        
        // Calculate new price: newPrice = oldPrice * (1 + fundingRate)
        // Using signed math for funding rate calculation
        int256 priceChange = int256(oldPrice) * fundingRate / int256(PRECISION);
        int256 newPriceInt = int256(oldPrice) + priceChange;
        
        // Ensure price doesn't go below a minimum threshold (0.1)
        require(newPriceInt >= int256(PRECISION / 10), "Price would be too low");
        
        uint256 newPrice = uint256(newPriceInt);
        
        // Update state
        currentPrice = newPrice;
        lastUpdateTime = block.timestamp;
        
        // Update total funding captured
        if (fundingRate > 0) {
            totalFundingCaptured += uint256(fundingRate);
        } else {
            // Handle negative funding (funding paid out)
            uint256 absRate = uint256(-fundingRate);
            if (totalFundingCaptured >= absRate) {
                totalFundingCaptured -= absRate;
            } else {
                totalFundingCaptured = 0;
            }
        }
        
        // Record the update
        fundingHistory.push(FundingUpdate({
            timestamp: block.timestamp,
            fundingRate: fundingRate,
            oldPrice: oldPrice,
            newPrice: newPrice
        }));
        
        emit PriceUpdated(
            block.timestamp,
            fundingRate,
            oldPrice,
            newPrice,
            totalFundingCaptured
        );
    }
    
    function authorizeUpdater(address updater) external onlyOwner {
        require(updater != address(0), "Invalid updater address");
        authorizedUpdaters[updater] = true;
        emit UpdaterAuthorized(updater);
    }
    
    function revokeUpdater(address updater) external onlyOwner {
        authorizedUpdaters[updater] = false;
        emit UpdaterRevoked(updater);
    }
    
    function getLatestUpdate() external view returns (FundingUpdate memory) {
        require(fundingHistory.length > 0, "No updates available");
        return fundingHistory[fundingHistory.length - 1];
    }
    
    function getFundingHistory(uint256 limit) external view returns (FundingUpdate[] memory) {
        uint256 length = fundingHistory.length;
        uint256 returnLength = limit > length ? length : limit;
        
        FundingUpdate[] memory recentHistory = new FundingUpdate[](returnLength);
        
        for (uint256 i = 0; i < returnLength; i++) {
            recentHistory[i] = fundingHistory[length - returnLength + i];
        }
        
        return recentHistory;
    }
    
    function getTimeUntilNextUpdate() external view returns (uint256) {
        uint256 nextUpdateTime = lastUpdateTime + MIN_UPDATE_INTERVAL;
        if (block.timestamp >= nextUpdateTime) {
            return 0;
        }
        return nextUpdateTime - block.timestamp;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencySetPrice(uint256 newPrice) external onlyOwner whenPaused {
        require(newPrice > 0, "Price must be positive");
        require(newPrice >= PRECISION / 10, "Price too low");
        
        uint256 oldPrice = currentPrice;
        currentPrice = newPrice;
        lastUpdateTime = block.timestamp;
        
        // Calculate implied funding rate for record keeping
        int256 impliedFundingRate = (int256(newPrice) - int256(oldPrice)) * int256(PRECISION) / int256(oldPrice);
        
        fundingHistory.push(FundingUpdate({
            timestamp: block.timestamp,
            fundingRate: impliedFundingRate,
            oldPrice: oldPrice,
            newPrice: newPrice
        }));
        
        emit PriceUpdated(
            block.timestamp,
            impliedFundingRate,
            oldPrice,
            newPrice,
            totalFundingCaptured
        );
    }
}