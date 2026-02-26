// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DAOTimelockController
 * @author Kalyan
 * @notice Acts as the gatekeeper between a passed governance vote and actual execution.
 * Even after a proposal passes, it cannot execute immediately - it must wait here
 * for the minimum delay period, giving the community time to react.
 * @dev Wraps OpenZeppelin's TimelockController.
 * The Timelock is the actual owner of all protocol contracts - not the Governor.
 * Governor just schedules operations here. Timelock executes them.
 *
 * Role System:
 * PROPOSER_ROLE → Only the Governor contract can queue proposals
 * EXECUTOR_ROLE → Anyone can execute after delay (permissionless)
 * CANCELLER_ROLE → Gaurdian multisig can cancel malicious proposals during delay
 * TIMELOCK_ADMIN_ROLE → Managed by the Timelock itself after setup
 */

contract DAOTimelockController is TimelockController {
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Timelock with delay and role assignments
     * @param minDelay Minium seconds before a queued proposal can execute
     * @param proposers Array of addresses that can queue proposals (should be Governor only)
     * @param executors Array of addresses that can execute proposals (address(0) = anyone)
     * @param admin Optional admin address for initial setup - should be renounced after deploy
     */
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
