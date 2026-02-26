// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {GovernanceToken} from "../../src/GovernanceToken.sol";
import {DeployDAO} from "../../script/DeployDAO.s.sol";

/**
 * @title GovernanceTokenTest
 * @author Kalyan
 * @notice Unit tests for GovernanceToken contract
 * @dev Tests are isolated - no Governor or Timelock needed here
 * We test GovernanceToken behaviour directly
 * 
 * Test Categories:
 *  - Deployment state
 *  - initializeGoverner
 *  - Minting
 *  - Voting power / delegation
 *  - Access control
 */

contract GovernanceTokenTest is Test {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    GovernanceToken public token;

    address public deployer = makeAddr("deployer");
    address public governor = makeAddr("governer");
    address public alice    = makeAddr("alice");
    address public bob      = makeAddr("bob");
    address public attacker = makeAddr("attacker");

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 value);

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {

        token = new GovernanceToken();

    }

     /*//////////////////////////////////////////////////////////////
                    1. DEPLOYMENT STATE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deployer should receive INITIAL_SUPPLY on deploy
     */
    function test_InitialSupplyMintedToDeployer() public view {
        assertEq(token.balanceOf(address(this)), token.INITIAL_SUPPLY());
    }

    /**
     * @notice Total supply should equal INITIAL_SUPPLY at deploy
     */
    function test_TotalSupplyEqualsInitialSupply() public view {
        assertEq(token.totalSupply(), token.INITIAL_SUPPLY());
    }

    /**
     * @notice Governor should be zero address before initialization
     */
    function test_GovernorIsZeroAddressAtDeploy() public view {
        assertEq(token.governor(), address(0));
    }

    /**
     * @notice Token name and symbol should be correct
     */
    function test_TokenMetadata() public view {
        assertEq(token.name(), "GovernanceToken");
        assertEq(token.symbol(), "GT");
    }

    /*//////////////////////////////////////////////////////////////
                    2. INITIALIZE GOVERNOR TESTS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Deployer should be able to initialize governor successfully
     */
    function test_DeployerCanInitializeGovernor() public {

        token.initializeGovernor(governor);

        assertEq(token.governor(), governor);
    }

    /**
     * @notice Non-deployer should not be able to initialize governor
     */
    function test_Revert_AttackerCannotInitializeGovernor() public {
        vm.prank(attacker);
        vm.expectRevert(GovernanceToken.GovernanceToken__NotDeployer.selector);
        token.initializeGovernor(attacker);
    }

    /**
     * @notice Governor cannot be initialized twice — AlreadyInitialized
     */
    function test_Revert_CannotInitializeGovernorTwice() public {

        token.initializeGovernor(governor);

        vm.expectRevert(GovernanceToken.GovernanceToken__AlreadyInitialized.selector);
        token.initializeGovernor(governor);

    }

    /**
     * @notice Cannot initialize governor with zero address
     */
    function test_Revert_CannotInitializeGovernorWithZeroAddress() public {

        vm.expectRevert(GovernanceToken.GovernanceToken__ZeroAddress.selector);
        token.initializeGovernor(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        3. MINTING TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Governor should be able to mint tokens to any address
     */
    function test_GovernorCanMint() public {
        // Setup — initialize governor first

        token.initializeGovernor(governor);

        uint256 mintAmount = 500e18;
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.prank(governor);
        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), aliceBalanceBefore + mintAmount);
    }

    /**
     * @notice Non-governor should not be able to mint
     */
    function test_Revert_AttackerCannotMint() public {

        token.initializeGovernor(governor);

        vm.prank(attacker);
        vm.expectRevert(GovernanceToken.GovernanceToken__NotGovernor.selector);
        token.mint(attacker, 1000e18);
    }

    /**
     * @notice Deployer should not be able to mint after governor is set
     * @dev Deployer only controls initialization — not minting
     */
    function test_Revert_DeployerCannotMint() public {

        token.initializeGovernor(governor);


        vm.expectRevert(GovernanceToken.GovernanceToken__NotGovernor.selector);
        token.mint(deployer, 1000e18);
    }

    /**
     * @notice Minting beyond MAX_SUPPLY should revert
     */
    function test_Revert_CannotMintBeyondMaxSupply() public {

        token.initializeGovernor(governor);

        // Try to mint more than remaining supply
        uint256 remaining = token.MAX_SUPPLY() - token.totalSupply();
        uint256 overLimit = remaining + 1e18;

        vm.prank(governor);
        vm.expectRevert(GovernanceToken.GovernanceToken__MaxSupplyExceeded.selector);
        token.mint(alice, overLimit);
    }

    /**
     * @notice Minting exactly up to MAX_SUPPLY should succeed
     */
    function test_CanMintUpToMaxSupply() public {

        token.initializeGovernor(governor);

        uint256 remaining = token.MAX_SUPPLY() - token.totalSupply();

        vm.prank(governor);
        token.mint(alice, remaining);

        assertEq(token.totalSupply(), token.MAX_SUPPLY());
    }

     /*//////////////////////////////////////////////////////////////
                    4. VOTING POWER SNAPSHOT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Voting power is zero before self-delegation
     * @dev ERC20Votes requires explicit delegation to activate voting power
     * This is critical — tokens without delegation don't count as votes
     */
    function test_VotingPowerZeroBeforeDelegation() public view {
        assertEq(token.getVotes(deployer), 0);
    }

    /**
     * @notice Voting power activates after self-delegation
     */
    function test_VotingPowerAfterSelfDelegation() public {

        token.delegate(address(this)); // ← test contract self-delegates

        assertEq(token.getVotes(address(this)), token.INITIAL_SUPPLY());
    }

    /**
     * @notice Delegating to another address transfers voting power
     */
    function test_DelegationTransfersVotingPower() public {
        // Deployer delegates to alice

        token.delegate(alice);

        assertEq(token.getVotes(alice), token.INITIAL_SUPPLY());
        assertEq(token.getVotes(address(this)), 0); // deployer has no voting power anymore
    }

    /**
     * @notice Snapshot captures voting power at a specific block
     * @dev getPastVotes returns power at snapshot block — not current block
     * This is what Governor uses to prevent flash loan vote manipulation
     */
    function test_SnapshotCapturesVotingPowerAtBlock() public {
        // Deployer self-delegates

        token.delegate(address(this));

        // Record block and voting power
        uint256 snapshotBlock = block.number;
        uint256 powerAtSnapshot = token.getVotes(address(this));

        // Move to next block
        vm.roll(block.number + 1);

        // Transfer tokens to alice — deployer's current power drops

        token.transfer(alice, 500_000e18);

        // Current voting power reduced
        assertLt(token.getVotes(address(this)), powerAtSnapshot);

        // But snapshot at old block still shows original power
        assertEq(token.getPastVotes(address(this), snapshotBlock), powerAtSnapshot);
    }

    /**
     * @notice Voting power updates correctly when tokens are minted
     */
    function test_VotingPowerUpdatesAfterMint() public {

        token.initializeGovernor(governor);

        // Alice self-delegates
        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), 0); // no tokens yet

        // Governor mints to alice
        vm.prank(governor);
        token.mint(alice, 1000e18);

        assertEq(token.getVotes(alice), 1000e18);
    }

    /**
     * @notice Voting power of delegatee updates when delegator receives tokens
     */
    function test_DelegateeVotingPowerUpdatesWithDelegatorBalance() public {

        token.initializeGovernor(governor);

        // Alice delegates to bob
        vm.prank(alice);
        token.delegate(bob);

        // Governor mints to alice
        vm.prank(governor);
        token.mint(alice, 2000e18);

        // Bob should have alice's voting power
        assertEq(token.getVotes(bob), 2000e18);
        assertEq(token.getVotes(alice), 0); // alice delegated away
    }
}