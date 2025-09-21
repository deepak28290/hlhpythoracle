// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract MockUSDC is ERC20, Ownable, Pausable {
    uint8 private constant DECIMALS = 6; // USDC has 6 decimals
    uint256 public constant FAUCET_AMOUNT = 10_000 * 10**DECIMALS; // 10,000 MockUSDC
    uint256 public constant FAUCET_COOLDOWN = 24 hours;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**DECIMALS; // 1B MockUSDC max supply
    
    mapping(address => uint256) public lastFaucetUse;
    
    event FaucetUsed(address indexed user, uint256 amount, uint256 timestamp);
    event FaucetAmountChanged(uint256 oldAmount, uint256 newAmount);
    
    constructor() ERC20("Mock USDC", "MUSDC") Ownable(msg.sender) {
        // Mint initial supply to owner for distribution
        _mint(owner(), 100_000 * 10**DECIMALS);
    }
    
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    function faucet() external whenNotPaused {
        require(
            block.timestamp >= lastFaucetUse[msg.sender] + FAUCET_COOLDOWN,
            "Faucet cooldown period not met"
        );
        require(
            totalSupply() + FAUCET_AMOUNT <= MAX_SUPPLY,
            "Would exceed max supply"
        );
        
        lastFaucetUse[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        
        emit FaucetUsed(msg.sender, FAUCET_AMOUNT, block.timestamp);
    }
    
    function getFaucetCooldownRemaining(address user) external view returns (uint256) {
        uint256 nextFaucetTime = lastFaucetUse[user] + FAUCET_COOLDOWN;
        if (block.timestamp >= nextFaucetTime) {
            return 0;
        }
        return nextFaucetTime - block.timestamp;
    }
    
    function canUseFaucet(address user) external view returns (bool) {
        return block.timestamp >= lastFaucetUse[user] + FAUCET_COOLDOWN &&
               totalSupply() + FAUCET_AMOUNT <= MAX_SUPPLY;
    }
    
    function getTimeUntilNextFaucet(address user) external view returns (uint256) {
        if (lastFaucetUse[user] == 0) {
            return 0; // Can use immediately
        }
        
        uint256 nextAvailableTime = lastFaucetUse[user] + FAUCET_COOLDOWN;
        if (block.timestamp >= nextAvailableTime) {
            return 0;
        }
        return nextAvailableTime - block.timestamp;
    }
    
    // Admin functions
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "Burn amount exceeds allowance");
        
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "ETH transfer failed");
    }
    
    // Override transfer functions to add pause functionality
    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }
    
    // Receive function to accept ETH (though not used in this contract)
    receive() external payable {}
}