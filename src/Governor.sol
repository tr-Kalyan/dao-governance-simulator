// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title DAOGoverner
 * @author kalyan
 * @notice This contract is the brain of the DAO governance system
 * Token holders create proposals, vote on them, and if passed,
 * the proposal is queued in the Timelock and executed after a delay
 * @dev Extends OpenZeppelin's modular Governor contracts
 * No single human has admin rights - the contract itself is the authority.
 *
 * Governance Flow:
 * Propose → Voting Period → Queue in Timelock → Execute after delay
 */
contract DAOGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 _quorumPercentage
    )
        Governor("DAOGovernor")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumPercentage)
        GovernorTimelockControl(_timelock)
    {}

    /*//////////////////////////////////////////////////////////////
                        REQUIRED OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the voting delay - block between proposal creation and voting start
     * @dev GovernorSettings overrides the base Governor implementaion
     */
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @notice Returns the voting period — blocks during which votes are accepted
     * @dev GovernorSettings overrides the base Governor implementation
     */
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @notice Returns the quorum required for a proposal to pass at a given block
     * @param blockNumber The snapshot block to calculate quorum against
     * @dev GovernorVotesQuorumFraction calculates this as percentage of total supply
     */
    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    /**
     * @notice Returns the minimum tokens needed to submit a proposal
     * @dev GovernorSettings overrides the base Governor implementation
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @notice Returns whether a proposal needs to be queued in the timelock before execution
     * @dev GovernorTimelockControl requires queuing — proposals cannot skip the timelock
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @notice Queues proposal operations into the timelock
     * @dev Only called internally after a proposal succeeds
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Executes proposal operations from the timelock
     * @dev Only callable after timelock delay has passed
     */
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Cancels a proposal and removes it from the timelock queue if queued
     * @dev Can be called by proposer before voting ends or by guardian
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Returns the executor address — the timelock contract
     * @dev All executed proposals flow through the timelock, not the Governor directly
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }

    /**
     * @notice Returns the current state of a proposal
     * @param proposalId The ID of the proposal to check
     * @dev GovernorTimelockControl overrides base state to account for timelock queuing status
     * A proposal can be: Pending, Active, Canceled, Defeated, Succeeded, Queued, Expired, Executed
     */
    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }
}
