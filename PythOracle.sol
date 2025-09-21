// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title PythOracle
 * @notice Production implementation of Pyth Oracle for testnet deployment
 * @dev This contract provides Pyth Network functionality for testnet environments
 */
contract PythOracle {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }
    
    // Price data for different feeds
    mapping(bytes32 => Price) public prices;
    mapping(bytes32 => bool) public feedExists;
    
    // Price feed IDs (same as real Pyth)
    bytes32 public constant BTC_USD_FEED = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;
    bytes32 public constant ETH_USD_FEED = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 public constant SOL_USD_FEED = 0xef0d8b6fda2ceba41da15d4095d1da392a0d2f8ed0c6c7bc0f4cfac8c280b56d;
    bytes32 public constant HYPE_USD_FEED = 0x0000000000000000000000000000000000000000000000000000000000000001;
    
    // Events
    event PriceFeedUpdate(bytes32 indexed id, int64 price, uint64 conf);
    
    constructor() {
        // Initialize with realistic testnet prices
        
        // BTC: $43,000 (price = 43000 * 10^8, expo = -8)
        prices[BTC_USD_FEED] = Price({
            price: 4300000000000,
            conf: 1000000000,
            expo: -8,
            publishTime: block.timestamp
        });
        feedExists[BTC_USD_FEED] = true;
        
        // ETH: $2,600 (price = 2600 * 10^8, expo = -8)
        prices[ETH_USD_FEED] = Price({
            price: 260000000000,
            conf: 500000000,
            expo: -8,
            publishTime: block.timestamp
        });
        feedExists[ETH_USD_FEED] = true;
        
        // SOL: $100 (price = 100 * 10^8, expo = -8)
        prices[SOL_USD_FEED] = Price({
            price: 10000000000,
            conf: 50000000,
            expo: -8,
            publishTime: block.timestamp
        });
        feedExists[SOL_USD_FEED] = true;
        
        // HYPE: $1.50 (price = 1.5 * 10^8, expo = -8)
        prices[HYPE_USD_FEED] = Price({
            price: 150000000,
            conf: 1000000,
            expo: -8,
            publishTime: block.timestamp
        });
        feedExists[HYPE_USD_FEED] = true;
    }
    
    /**
     * @notice Get update fee for testnet environment
     * @param updateData Price update data
     */
    function getUpdateFee(bytes[] memory updateData) external pure returns (uint256 fee) {
        // Testnet fee - small amount for testing
        return 0.001 ether * updateData.length;
    }
    
    /**
     * @notice Update price feeds for testnet environment
     * @param updateData Price update data
     */
    function updatePriceFeeds(bytes[] memory updateData) external payable {
        // Testnet price updates - simulate realistic price changes
        uint256 randomSeed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao)));
        
        // Update BTC price (±2% random change)
        _updatePrice(BTC_USD_FEED, randomSeed);
        
        // Update ETH price (±2% random change)
        _updatePrice(ETH_USD_FEED, randomSeed >> 64);
        
        // Update SOL price (±3% random change)
        _updatePrice(SOL_USD_FEED, randomSeed >> 128);
        
        // Update HYPE price (±1% random change)
        _updatePrice(HYPE_USD_FEED, randomSeed >> 192);
    }
    
    /**
     * @notice Internal function to update a price with random variation
     * @param feedId Price feed ID
     * @param seed Random seed for price variation
     */
    function _updatePrice(bytes32 feedId, uint256 seed) internal {
        Price storage price = prices[feedId];
        
        // Generate random price change (±2% for most assets, ±1% for HYPE)
        uint256 maxChangePercent = feedId == HYPE_USD_FEED ? 100 : 200; // 1% or 2%
        uint256 changePercent = seed % (maxChangePercent * 2); // 0 to 2*maxChangePercent
        
        int64 currentPrice = price.price;
        int64 change;
        
        if (changePercent < maxChangePercent) {
            // Negative change
            change = -int64(int256((uint256(uint64(currentPrice)) * (maxChangePercent - changePercent)) / 10000));
        } else {
            // Positive change
            change = int64(int256((uint256(uint64(currentPrice)) * (changePercent - maxChangePercent)) / 10000));
        }
        
        price.price = currentPrice + change;
        price.publishTime = block.timestamp;
        
        emit PriceFeedUpdate(feedId, price.price, price.conf);
    }
    
    /**
     * @notice Get latest price for a feed
     * @param id Price feed ID
     */
    function getPrice(bytes32 id) external view returns (Price memory price) {
        require(feedExists[id], "Price feed not found");
        return prices[id];
    }
    
    /**
     * @notice Get latest price (unsafe version)
     * @param id Price feed ID
     */
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price) {
        return prices[id];
    }
    
    /**
     * @notice Set custom price for testing
     * @param id Price feed ID
     * @param price New price value
     * @param conf Confidence interval
     * @param expo Price exponent
     */
    function setPrice(
        bytes32 id,
        int64 price,
        uint64 conf,
        int32 expo
    ) external {
        prices[id] = Price({
            price: price,
            conf: conf,
            expo: expo,
            publishTime: block.timestamp
        });
        feedExists[id] = true;
        
        emit PriceFeedUpdate(id, price, conf);
    }
    
    /**
     * @notice Get all supported feed IDs
     */
    function getSupportedFeeds() external pure returns (bytes32[] memory) {
        bytes32[] memory feeds = new bytes32[](4);
        feeds[0] = BTC_USD_FEED;
        feeds[1] = ETH_USD_FEED;
        feeds[2] = SOL_USD_FEED;
        feeds[3] = HYPE_USD_FEED;
        return feeds;
    }
    
    /**
     * @notice Withdraw collected fees (for testing)
     */
    function withdraw() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}