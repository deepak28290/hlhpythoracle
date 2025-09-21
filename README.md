# hlhpythoracle
a real-time oracle consuming multiple Pyth price feeds (BTC, ETH, SOL, HYPE), batching updates via updatePriceFeeds, and computing funding rates on-chain with sub-second latency. This eliminated 8-hour delays by streaming live prices through Hermes → adapter contracts → HIP-3 markets, enabling tradable funding rate derivatives.
