# DAO Governance Simulator

A production-level onchain governance system built with a security-first mindset. This project simulates how real DAOs like Compound, Uniswap, and Aave govern themselves — where token holders vote on proposals that execute real onchain actions, with no centralized admin or multisig.

Built to understand governance architecture deeply, identify attack surfaces, and simulate real-world exploits in a controlled environment.

---

## Architecture

```
Token Holder → Creates Proposal → Voting Period → Timelock Delay → Execution → Onchain State Change
```

### Contracts

| Contract | Description |
|---|---|
| `GovernanceToken.sol` | ERC20Votes token with snapshot-based voting power. Only Governor can mint. |
| `Governor.sol` | Proposal lifecycle — creation, voting, queuing, execution. The brain of the system. |
| `TimelockController.sol` | Gatekeeper between a passed vote and execution. Enforces delay for community reaction. |
| `Treasury.sol` | Holds DAO funds (ETH + ERC20). Only Timelock can release funds. |

### Contract Interaction

```
GovernanceToken
    ↓ voting power snapshots
DAOGovernor  ←→  DAOTimelockController  →  DAOTreasury
    ↓                   ↓                       ↓
proposals           role system             fund releases
voting              execution delay         ETH + ERC20
quorum checks       cancellation            internal accounting
```

---

## Security Design Decisions

### Snapshot-Based Voting Power
Voting power is measured at the block **before** a proposal is created, not at vote time. This prevents flash loan attacks where an attacker borrows tokens, votes, and returns them in the same block.

### Timelock Owns Everything
The Timelock contract — not the Governor — is the owner of all protocol contracts. Even if the Governor has a bug, the attacker cannot execute anything instantly. They must wait through the delay, during which the community can cancel the proposal.

### Role System
```
PROPOSER_ROLE  → Governor contract only (no human can queue proposals directly)
EXECUTOR_ROLE  → address(0) — anyone can trigger execution after delay (permissionless)
CANCELLER_ROLE → Guardian address (deployer for now, Gnosis Safe in production)
ADMIN_ROLE     → Renounced after deploy — point of no return
```

### Initialization Vulnerability (Fixed)
`GovernanceToken` uses a one-time `initializeGovernor()` function instead of a constructor parameter to break the circular dependency between Token and Governor. The function is protected by `deployer` access control to prevent front-running during deployment.

### Internal Accounting
Treasury tracks deposits via internal mappings (`ethBalance`, `erc20Balances`) instead of raw `address(this).balance`. This prevents `selfdestruct` inflation attacks where an attacker forces ETH into the contract to manipulate balance checks.

### Reentrancy Protection
ETH releases use `.call()` (required for modern Solidity) protected by both `nonReentrant` modifier and strict Checks-Effects-Interactions pattern — state updates before external calls.

---

## Deployment

Uses **CREATE2** for all four contracts so every address is deterministic and pre-computable before any deployment happens. This solves the circular dependency between GovernanceToken (needs Governor address) and Governor (needs GovernanceToken address).

```bash
forge script script/DeployDAO.s.sol --rpc-url <RPC_URL> --broadcast
```

### Deploy Order
```
1. Pre-compute all four addresses via CREATE2
2. Deploy GovernanceToken
3. Deploy TimelockController
4. Deploy Governor (token + timelock addresses)
5. Deploy Treasury (timelock address)
6. Initialize Governor in GovernanceToken (one-time call)
7. Grant Timelock roles
8. Renounce admin role → system fully decentralized
```

### Parameters

| Parameter | Value | Reasoning |
|---|---|---|
| Voting Delay | 7200 blocks (~1 day) | Time to notice a proposal before voting opens |
| Voting Period | 50400 blocks (~1 week) | Broad participation window |
| Proposal Threshold | 100,000 GT (10% of initial supply) | Prevents proposal spam |
| Quorum | 4% of total supply | Industry standard — Compound, Uniswap baseline |
| Timelock Delay | 2 days | Emergency window to cancel malicious proposals |
| Initial Supply | 1,000,000 GT | Bootstrap supply for early governance |
| Max Supply | 10,000,000 GT | Hard cap — baked into bytecode as a constant |

---

## Known Attack Surfaces (Intentional — for Simulation)

These are documented attack vectors that will be simulated in tests:

| Attack | Description | Mitigation In Place |
|---|---|---|
| Flash Loan Governance | Borrow tokens, vote, return in same block | Snapshot voting blocks this |
| Treasury Drain Proposal | Pass a proposal to release all funds | Timelock delay + canceller role |
| Proposal Spam | Flood governance with low-effort proposals | Proposal threshold (100k GT) |
| Low Quorum Capture | Pass proposals when participation is low | 4% quorum requirement |
| Front-run Initialization | Call `initializeGovernor` before deployer | `deployer` access control |
| Timelock Role Misconfiguration | EOA as PROPOSER bypasses governance | Only Governor has PROPOSER_ROLE |

---

## Project Status

### Completed
- [x] `GovernanceToken.sol` — ERC20Votes with snapshot support, controlled minting
- [x] `Governor.sol` — Full proposal lifecycle with timelock integration
- [x] `TimelockController.sol` — Role-based access, delay enforcement
- [x] `Treasury.sol` — ETH + ERC20 management, reentrancy protection, internal accounting
- [x] `DeployDAO.s.sol` — CREATE2 deterministic deployment, role setup, admin renounce

### In Progress
- [ ] Unit Tests — GovernanceToken, Treasury in isolation
- [ ] Integration Tests — Full governance flow end to end
- [ ] Attack Simulation Tests — Flash loan, drain proposal, low quorum exploits

### Planned
- [ ] Gnosis Safe integration as CANCELLER_ROLE (production hardening)
- [ ] Governance-controlled parameter updates (voting delay, quorum)
- [ ] Frontend dashboard to visualize proposal lifecycle

---

## Installation

```bash
git clone https://github.com/tr-Kalyan/dao-governance-simulator
cd dao-governance-simulator
forge install
forge build
```

### Dependencies
- [Foundry](https://getfoundry.sh/)
- [OpenZeppelin Contracts v5](https://github.com/OpenZeppelin/openzeppelin-contracts)

---

## Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvvv

# Run specific test file
forge test --match-path test/unit/GovernanceTokenTest.t.sol
```

---

## Author

Built by [@tr-Kalyan](https://github.com/tr-Kalyan) — Web3 security researcher and smart contract auditor.

Focus areas: DeFi protocol security, governance attack vectors, bug bounty hunting on Immunefi and Sherlock.

---

## Disclaimer

This project is for educational and research purposes. The attack simulations are intentional and exist to study governance vulnerabilities in a controlled environment.