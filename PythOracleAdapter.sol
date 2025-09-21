// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Pyth Network interface (simplified for MVP)
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }
    
    function getUpdateFee(bytes[] memory updateData) external view returns (uint256 fee);
    function updatePriceFeeds(bytes[] memory updateData) external payable;
    function getPrice(bytes32 id) external view returns (Price memory price);
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}

/**
 * @title PythOracleAdapter
 * @notice Integrates Pyth Network price feeds for real-time funding rate calculations
 * @dev This contract consumes Pyth price feeds and calculates funding rates for HIP-3 markets
 */
contract PythOracleAdapter is Ownable, Pausable {
    IPyth public immutable pythOracle;
    
    // Price feed IDs for different assets (mainnet values)
    bytes32 public constant BTC_USD_FEED = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    bytes32 public constant ETH_USD_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant SOL_USD_FEED = 0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d;
    bytes32 public constant HYPE_USD_FEED = 0x0000000000000000000000000000000000000000000000000000000000000000; // Placeholder
    
    // Funding rate data structure
    struct FundingRateData {
        uint256 cumulativeFunding;  // Cumulative funding index
        int256 lastFundingRate;     // Last funding rate (can be negative)
        uint256 lastUpdateTime;     // Last update timestamp
        uint256 lastPrice;          // Last recorded price
    }
    
    // Market funding data
    mapping(string => FundingRateData) public marketFundingData;
    mapping(bytes32 => string) public feedIdToSymbol;
    
    // Configuration
    uint256 public constant FUNDING_PRECISION = 1e18;
    uint256 public constant RATE_PRECISION = 1e6;  // 0.01% = 100
    uint256 public minUpdateInterval = 60;  // Minimum 1 minute between updates
    uint256 public maxFundingRate = 10000;  // 1% max funding rate per period
    
    // Events
    event FundingRateUpdated(
        string indexed symbol,
        int256 fundingRate,
        uint256 cumulativeFunding,
        uint256 price,
        uint256 timestamp
    );
    
    event PriceFeedUpdated(
        bytes32 indexed feedId,
        int64 price,
        uint64 confidence,
        uint256 timestamp
    );
    
    event EmergencyWithdraw(address indexed to, uint256 amount);
    
    constructor(address _pythOracle) Ownable(msg.sender) {
        require(_pythOracle != address(0), "Invalid Pyth oracle address");
        pythOracle = IPyth(_pythOracle);
        
        // Initialize feed mappings
        feedIdToSymbol[BTC_USD_FEED] = "BTC";
        feedIdToSymbol[ETH_USD_FEED] = "ETH";
        feedIdToSymbol[SOL_USD_FEED] = "SOL";
        feedIdToSymbol[HYPE_USD_FEED] = "HYPE";
        
        // Initialize market data
        marketFundingData["BTC"] = FundingRateData({
            cumulativeFunding: FUNDING_PRECISION,
            lastFundingRate: 0,
            lastUpdateTime: block.timestamp,
            lastPrice: 0
        });
        
        marketFundingData["ETH"] = FundingRateData({
            cumulativeFunding: FUNDING_PRECISION,
            lastFundingRate: 0,
            lastUpdateTime: block.timestamp,
            lastPrice: 0
        });
        
        marketFundingData["SOL"] = FundingRateData({
            cumulativeFunding: FUNDING_PRECISION,
            lastFundingRate: 0,
            lastUpdateTime: block.timestamp,
            lastPrice: 0
        });
        
        marketFundingData["HYPE"] = FundingRateData({
            cumulativeFunding: FUNDING_PRECISION,
            lastFundingRate: 0,
            lastUpdateTime: block.timestamp,
            lastPrice: 0
        });
    }
    
    /**
     * @notice Update price feeds and calculate funding rates
     * @param priceUpdateData Array of price update data from Pyth
     * @param feedIds Array of feed IDs to update
     */
    function updatePriceFeeds(
        bytes[] calldata priceUpdateData,
        bytes32[] calldata feedIds
    ) external payable whenNotPaused {
        // Get required fee from Pyth
        uint256 fee = pythOracle.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee");
        
        // Update Pyth price feeds
        pythOracle.updatePriceFeeds{value: fee}(priceUpdateData);
        
        // Update funding rates for each feed
        for (uint i = 0; i < feedIds.length; i++) {
            _updateFundingRate(feedIds[i]);
        }
        
        // Refund excess fee
        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }
    }
    
    /**
     * @notice Internal function to update funding rate for a specific feed
     * @param feedId Price feed ID to update
     */
    function _updateFundingRate(bytes32 feedId) internal {
        string memory symbol = feedIdToSymbol[feedId];
        require(bytes(symbol).length > 0, "Unknown feed ID");
        
        FundingRateData storage data = marketFundingData[symbol];
        
        // Check minimum update interval
        require(
            block.timestamp >= data.lastUpdateTime + minUpdateInterval,
            "Update too frequent"
        );
        
        // Get latest price from Pyth
        IPyth.Price memory pythPrice = pythOracle.getPrice(feedId);
        
        // Convert Pyth price to standard format (handle exponent)
        uint256 currentPrice = _convertPythPrice(pythPrice);
        
        // Calculate funding rate if we have previous price
        if (data.lastPrice > 0) {
            int256 fundingRate = _calculateFundingRate(
                data.lastPrice,
                currentPrice,
                block.timestamp - data.lastUpdateTime
            );
            
            // Apply funding rate cap
            if (fundingRate > int256(maxFundingRate)) {
                fundingRate = int256(maxFundingRate);
            } else if (fundingRate < -int256(maxFundingRate)) {
                fundingRate = -int256(maxFundingRate);
            }
            
            // Update cumulative funding
            if (fundingRate >= 0) {
                data.cumulativeFunding = data.cumulativeFunding * 
                    (RATE_PRECISION + uint256(fundingRate)) / RATE_PRECISION;
            } else {
                data.cumulativeFunding = data.cumulativeFunding * 
                    (RATE_PRECISION - uint256(-fundingRate)) / RATE_PRECISION;
            }
            
            data.lastFundingRate = fundingRate;
        }
        
        // Update state
        data.lastPrice = currentPrice;
        data.lastUpdateTime = block.timestamp;
        
        // Emit events
        emit PriceFeedUpdated(feedId, pythPrice.price, pythPrice.conf, block.timestamp);
        emit FundingRateUpdated(
            symbol,
            data.lastFundingRate,
            data.cumulativeFunding,
            currentPrice,
            block.timestamp
        );
    }
    
    /**
     * @notice Calculate funding rate based on price change
     * @param lastPrice Previous price
     * @param currentPrice Current price
     * @param timeElapsed Time elapsed since last update
     */
    function _calculateFundingRate(
        uint256 lastPrice,
        uint256 currentPrice,
        uint256 timeElapsed
    ) internal pure returns (int256) {
        // Simple funding rate calculation based on price momentum
        // Positive rate = longs pay shorts, negative = shorts pay longs
        
        if (currentPrice > lastPrice) {
            uint256 priceIncrease = currentPrice - lastPrice;
            uint256 rate = (priceIncrease * RATE_PRECISION) / lastPrice;
            
            // Annualize the rate (assuming 8 hour funding periods)
            rate = (rate * 8 hours) / timeElapsed;
            
            return int256(rate);
        } else if (lastPrice > currentPrice) {
            uint256 priceDecrease = lastPrice - currentPrice;
            uint256 rate = (priceDecrease * RATE_PRECISION) / lastPrice;
            
            // Annualize the rate
            rate = (rate * 8 hours) / timeElapsed;
            
            return -int256(rate);
        }
        
        return 0;
    }
    
    /**
     * @notice Convert Pyth price format to standard uint256
     * @param pythPrice Price data from Pyth
     */
    function _convertPythPrice(IPyth.Price memory pythPrice) internal pure returns (uint256) {
        require(pythPrice.price > 0, "Invalid price");
        
        uint256 price = uint256(uint64(pythPrice.price));
        
        // Handle negative exponent (most common case)
        if (pythPrice.expo < 0) {
            uint256 divisor = 10 ** uint256(uint32(-pythPrice.expo));
            // Scale to 18 decimals
            return (price * FUNDING_PRECISION) / divisor;
        } else {
            // Handle positive exponent
            uint256 multiplier = 10 ** uint256(uint32(pythPrice.expo));
            return price * multiplier * FUNDING_PRECISION;
        }
    }
    
    /**
     * @notice Get current funding rate for a symbol
     * @param symbol Asset symbol
     */
    function getFundingRate(string calldata symbol) external view returns (int256) {
        return marketFundingData[symbol].lastFundingRate;
    }
    
    /**
     * @notice Get cumulative funding index for a symbol
     * @param symbol Asset symbol
     */
    function getCumulativeFunding(string calldata symbol) external view returns (uint256) {
        return marketFundingData[symbol].cumulativeFunding;
    }
    
    /**
     * @notice Get complete funding data for a symbol
     * @param symbol Asset symbol
     */
    function getFundingData(string calldata symbol) 
        external 
        view 
        returns (FundingRateData memory) 
    {
        return marketFundingData[symbol];
    }
    
    /**
     * @notice Update configuration parameters
     * @param _minUpdateInterval New minimum update interval
     * @param _maxFundingRate New maximum funding rate
     */
    function updateConfig(
        uint256 _minUpdateInterval,
        uint256 _maxFundingRate
    ) external onlyOwner {
        minUpdateInterval = _minUpdateInterval;
        maxFundingRate = _maxFundingRate;
    }
    
    /**
     * @notice Pause contract operations
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause contract operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @notice Emergency withdrawal function
     * @param to Address to send funds to
     */
    function emergencyWithdraw(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        to.transfer(balance);
        emit EmergencyWithdraw(to, balance);
    }
    
    /**
     * @notice Receive function to accept ETH
     */
    receive() external payable {}
}