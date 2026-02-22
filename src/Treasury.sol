// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title DAOTreasury
 * @author Kalyan
 * @notice Holds the DAO's funds - ETH and ERC20 tokens.
 * Only the Timelock contract can move funds out.
 * This is the target contract that governance proposals actually call.
 * @dev All fund movements require a password governance vote that has
 * cleared the timelock delay. No individual human can move funds.
 * 
 * Attack Surface (intentaion for simulator)
 *  - Malicious proposal draining entire treasury
 *  - Reentrancy on ETH release
 *  - ERC20 approval exploits
 */

contract DAOTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The timelock contract — only address that can move funds
    address public immutable timelock;


    /// @notice Tracks ETH deposited through official channels
    uint256 public ethBalance;

    /// @notice Tracks ERC20 token balances deposited through official channels
    /// @dev token address => amount
    mapping(address => uint256) public erc20Balances;   

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error DAOTreasury__NotTimelock();
    error DAOTreasury__ZeroAddress();
    error DAOTreasury__ZeroAmount();
    error DAOTreasury__InsufficientBalance();
    error DAOTreasury__ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when ETH is deposited into the treasury
    event ETHDeposited(address indexed sender, uint256 amount);

    /// @notice Emitted when ERC20 tokens are deposited into the treasury
    event ERC20Deposited(address indexed token, address indexed sender, uint256 amount);

    /// @notice Emitted when ETH is released from the treasury
    event ETHReleased(address indexed to, uint256 amount);

    /// @notice Emitted when ERC20 tokens are released from the treasury
    event ERC20Released(address indexed token, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function to only the Timelock contract
    modifier onlyTimelock() {
        if (msg.sender != timelock) revert DAOTreasury__NotTimelock();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the treasury with the timelock as its sole authority
     * @param _timelock Address of the DAOTimelockController
     */
    constructor(address _timelock) {
        if (_timelock == address(0)) revert DAOTreasury__ZeroAddress();
        timelock = _timelock;
    }

     /*//////////////////////////////////////////////////////////////
                        RECEIVE ETH
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the treasury to receive ETH directly
     * @dev Anyone can deposit ETH — only timelock can take it out
     */
    receive() external payable {
        ethBalance += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits ERC20 tokens into the treasury and updates internal accounting
     * @param token Address of the ERC20 token
     * @param amount Amount to deposit
     * @dev Anyone can deposit — only timelock can withdraw
     */
    function depositERC20(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert DAOTreasury__ZeroAddress();
        if (amount == 0) revert DAOTreasury__ZeroAmount();

        erc20Balances[token] += amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit ERC20Deposited(token, msg.sender, amount);
    }

    /**
     * @notice Releases ETH from the treasury to a specified address
     * @param to Recipient address
     * @param amount Amount of ETH in wei to release
     * @dev nonReentrant prevents reentrancy via .call() callback
     * Checks-Effects-Interactions pattern strictly followed:
     * 1. Check balance
     * 2. No state to update (ETH balance handled by EVM)
     * 3. Interact via .call() last
     */
    function releaseETH(address to, uint256 amount) external onlyTimelock nonReentrant {
        if (to == address(0)) revert DAOTreasury__ZeroAddress();
        if (amount == 0) revert DAOTreasury__ZeroAmount();
        if (ethBalance < amount) revert DAOTreasury__InsufficientBalance(); // ← checks mapping not raw balance

        ethBalance -= amount; // ← effect: reduce tracked balance first
        
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert DAOTreasury__ETHTransferFailed();

        emit ETHReleased(to, amount);
    }

    /**
     * @notice Releases ERC20 tokens from the treasury to a specified address
     * @param token Address of the ERC20 token contract
     * @param to Recipient address
     * @param amount Amount of tokens to release
     * @dev SafeERC20 handles tokens that don't return bool on transfer
     * No reentrancy risk on ERC20 transfers but nonReentrant added for
     * defense in depth — malicious ERC20 tokens can have hooks
     */
    function releaseERC20(address token, address to, uint256 amount) external onlyTimelock nonReentrant {
        if (token == address(0)) revert DAOTreasury__ZeroAddress();
        if (to == address(0)) revert DAOTreasury__ZeroAddress();
        if (amount == 0) revert DAOTreasury__ZeroAmount();
        if (IERC20(token).balanceOf(address(this)) < amount) revert DAOTreasury__InsufficientBalance();

        erc20Balances[token] -= amount;

        IERC20(token).safeTransfer(to, amount);

        emit ERC20Released(token, to, amount);
    }
}