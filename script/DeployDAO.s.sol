// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {DAOGovernor} from "../src/Governor.sol";
import {DAOTimelockController} from "../src/TimelockController.sol";
import {DAOTreasury} from "../src/Treasury.sol";

/**
 * @title DeployDAO
 * @author Kalyan
 * @notice Deploys and wires all four DAO contracts together.
 * Uses CREATE2 for all contracts so every address is deterministic
 * and pre-computable before any deployment happens.
 * @dev Run with:
 * forge script script/DeployDAO.s.sol --rpc-url <RPC_URL> --broadcast
 *
 * Deploy Order:
 * 1. Pre-compute all four contract addresses via CREATE2
 * 2. Deploy GovernanceToken (no governor in constructor)
 * 3. Deploy TimelockController
 * 4. Deploy Governor (real token + timelock addresses)
 * 5. Deploy Treasury (real timelock address)
 * 6. Initialize Governor address in GovernanceToken (one-time call)
 * 7. Setup Timelock roles
 * 8. Renounce admin role — system fully decentralized
 */
contract DeployDAO is Script {

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Blocks before voting starts after proposal creation (1 day ~ 7200 blocks)
    uint48 public constant VOTING_DELAY = 7200;

    /// @notice Blocks during which voting is active (1 week ~ 50400 blocks)
    uint32 public constant VOTING_PERIOD = 50400;

    /// @notice Minimum tokens required to create a proposal (100k tokens)
    uint256 public constant PROPOSAL_THRESHOLD = 100_000e18;

    /// @notice Percentage of total supply required for quorum (4%)
    uint256 public constant QUORUM_PERCENTAGE = 4;

    /// @notice Minimum seconds before a queued proposal can execute (2 days)
    uint256 public constant MIN_TIMELOCK_DELAY = 2 days;

    /*//////////////////////////////////////////////////////////////
                            RUN FUNCTION
    //////////////////////////////////////////////////////////////*/

    function run() external returns (
        GovernanceToken token,
        DAOGovernor governor,
        DAOTimelockController timelock,
        DAOTreasury treasury
    ) {
        address deployer = msg.sender;

        // Deterministic salts — unique per deployer
        bytes32 tokenSalt    = keccak256(abi.encodePacked("GovernanceToken", deployer));
        bytes32 timelockSalt = keccak256(abi.encodePacked("DAOTimelock", deployer));
        bytes32 governorSalt = keccak256(abi.encodePacked("DAOGovernor", deployer));
        bytes32 treasurySalt = keccak256(abi.encodePacked("DAOTreasury", deployer));

        // Step 1: Pre-compute all addresses before deploying anything
        address precomputedToken = _precomputeAddress(
            type(GovernanceToken).creationCode,
            abi.encode(), // no constructor args
            tokenSalt,
            deployer
        );

        address precomputedTimelock = _precomputeAddress(
            type(DAOTimelockController).creationCode,
            abi.encode(
                MIN_TIMELOCK_DELAY,
                new address[](0),
                new address[](0),
                deployer
            ),
            timelockSalt,
            deployer
        );

        // Governor uses REAL token + timelock addresses — no placeholders
        address precomputedGovernor = _precomputeAddress(
            type(DAOGovernor).creationCode,
            abi.encode(
                precomputedToken,
                precomputedTimelock,
                VOTING_DELAY,
                VOTING_PERIOD,
                PROPOSAL_THRESHOLD,
                QUORUM_PERCENTAGE
            ),
            governorSalt,
            deployer
        );

        address precomputedTreasury = _precomputeAddress(
            type(DAOTreasury).creationCode,
            abi.encode(precomputedTimelock),
            treasurySalt,
            deployer
        );

        console2.log("=== PRE-COMPUTED ADDRESSES ===");
        console2.log("Token    :", precomputedToken);
        console2.log("Timelock :", precomputedTimelock);
        console2.log("Governor :", precomputedGovernor);
        console2.log("Treasury :", precomputedTreasury);

        vm.startBroadcast(deployer);

        // Step 2: Deploy GovernanceToken — no governor in constructor anymore
        token = new GovernanceToken{salt: tokenSalt}();
        console2.log("GovernanceToken deployed at:", address(token));
        require(address(token) == precomputedToken, "Token address mismatch");

        // Step 3: Deploy Timelock — proposers/executors empty, roles assigned later
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        timelock = new DAOTimelockController{salt: timelockSalt}(
            MIN_TIMELOCK_DELAY,
            proposers,
            executors,
            deployer
        );
        console2.log("Timelock deployed at:", address(timelock));
        require(address(timelock) == precomputedTimelock, "Timelock address mismatch");

        // Step 4: Deploy Governor with real token + timelock addresses
        governor = new DAOGovernor{salt: governorSalt}(
            token,
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_PERCENTAGE
        );
        console2.log("Governor deployed at:", address(governor));
        require(address(governor) == precomputedGovernor, "Governor address mismatch");

        // Step 5: Deploy Treasury
        treasury = new DAOTreasury{salt: treasurySalt}(address(timelock));
        console2.log("Treasury deployed at:", address(treasury));
        require(address(treasury) == precomputedTreasury, "Treasury address mismatch");

        // Step 6: Initialize Governor in GovernanceToken — one time call
        // This is the step that breaks the circular dependency cleanly
        token.initializeGovernor(address(governor));
        console2.log("Governor initialized in GovernanceToken");

        // Step 7: Setup Timelock roles
        _setupTimelockRoles(timelock, address(governor), deployer);

        vm.stopBroadcast();

        _logDeployment(address(token), address(governor), address(timelock), address(treasury));
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pre-computes a contract address using CREATE2 formula
     * @param creationCode The contract's type().creationCode
     * @param constructorArgs ABI encoded constructor arguments
     * @param salt Unique salt for this contract
     * @param deployer Address that will deploy the contract
     * @return Deterministic address where contract will land
     */
    function _precomputeAddress(
        bytes memory creationCode,
        bytes memory constructorArgs,
        bytes32 salt,
        address deployer
    ) internal pure returns (address) {
        bytes memory bytecode = abi.encodePacked(creationCode, constructorArgs);
        bytes32 bytecodeHash = keccak256(bytecode);

        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            bytecodeHash
        )))));
    }

    /**
     * @notice Wires up Timelock roles after all contracts are deployed
     * @param _timelock The deployed timelock contract
     * @param _governor The deployed governor contract
     * @param _deployer The deployer — admin role renounced at end
     * @dev Role assignments:
     * PROPOSER_ROLE       → Governor only — no human can queue proposals
     * EXECUTOR_ROLE       → address(0) — anyone can execute after delay
     * CANCELLER_ROLE      → deployer for now, upgrade to Gnosis Safe later
     * TIMELOCK_ADMIN_ROLE → renounced — point of no return
     */
    function _setupTimelockRoles(
        DAOTimelockController _timelock,
        address _governor,
        address _deployer
    ) internal {
        bytes32 proposerRole = _timelock.PROPOSER_ROLE();
        bytes32 executorRole = _timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = _timelock.CANCELLER_ROLE();
        bytes32 adminRole = _timelock.DEFAULT_ADMIN_ROLE();

        _timelock.grantRole(proposerRole, _governor);
        console2.log("PROPOSER_ROLE granted to Governor");

        _timelock.grantRole(executorRole, address(0));
        console2.log("EXECUTOR_ROLE granted to address(0) - permissionless");

        _timelock.grantRole(cancellerRole, _deployer);
        console2.log("CANCELLER_ROLE granted to deployer");

        // Point of no return — after this line nobody has admin
        _timelock.renounceRole(adminRole, _deployer);
        console2.log("TIMELOCK_ADMIN_ROLE renounced - system is fully decentralized");
    }

    /**
     * @notice Logs final deployment summary
     */
    function _logDeployment(
        address _token,
        address _governor,
        address _timelock,
        address _treasury
    ) internal pure {
        console2.log("\n=== DAO DEPLOYMENT SUMMARY ===");
        console2.log("GovernanceToken :", _token);
        console2.log("DAOGovernor     :", _governor);
        console2.log("Timelock        :", _timelock);
        console2.log("Treasury        :", _treasury);
        console2.log("==============================\n");
    }
}