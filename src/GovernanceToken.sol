// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract GovernanceToken is ERC20, ERC20Votes {
    uint256 public constant MAX_SUPPLY = 10_000_000e18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    address public governor;
    address public immutable deployer;

    error GovernanceToken__NotGovernor();
    error GovernanceToken__AlreadyInitialized();
    error GovernanceToken__ZeroAddress();
    error GovernanceToken__MaxSupplyExceeded();
    error GovernanceToken__NotDeployer();

    modifier onlyGovernor() {
        if (msg.sender != governor) revert GovernanceToken__NotGovernor();
        _;
    }

    constructor() ERC20("GovernanceToken", "GT") EIP712("GovernanceToken", "1") {
        deployer = msg.sender;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function initializeGovernor(address _governor) external {
        if (msg.sender != deployer) revert GovernanceToken__NotDeployer();
        if (governor != address(0)) revert GovernanceToken__AlreadyInitialized();
        if (_governor == address(0)) revert GovernanceToken__ZeroAddress();
        governor = _governor;
    }

    function mint(address to, uint256 amount) external onlyGovernor {
        if (totalSupply() + amount > MAX_SUPPLY) revert GovernanceToken__MaxSupplyExceeded();
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }
}
