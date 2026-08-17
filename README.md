# HarryHowardAI Contracts

Foundry project containing the HarryHowardAI Token and HourlySquadGame smart contracts for BNB Smart Chain.

The intended networks are:

- BNB Smart Chain Mainnet — Chain ID `56`
- BNB Smart Chain Testnet — Chain ID `97`

Do not deploy these contracts to Ethereum, Polygon, Arbitrum, or another EVM network unless the entire frontend and backend configuration is intentionally migrated.

## Contracts

### HarryHowardAI Token

Source: `src/HarryHowardAI.sol`

`HarryHowardAI` is the HHA Token contract:

- ERC-20 name: `Harry Howard AI`
- Symbol: `HHA`
- Initial supply: 1,000,000,000 HHA
- Initial supply is minted to the deployer
- Uses the default 18 decimals
- Burnable through `ERC20Burnable`
- Ownable through OpenZeppelin `Ownable`
- Supports EIP-2612 Permit through `ERC20Permit`

The deployed HHA address must match the Token address configured in the HarryHowardAI backend and frontend for the same BSC environment.

### HourlySquadGame

Source: `src/HourlySquadGame.sol`

`HourlySquadGame` is a four-faction, hourly Token betting game:

- Four factions: `0` through `3`
- One-hour rounds
- The final two minutes of each round are locked
- One bet per user per round
- Configurable maximum bet amount
- Default maximum bet: 1,000 Tokens, assuming 18 decimals
- Supports normal ERC-20 `approve` + `placeBet`
- Supports Permit-based relayed betting through `placeBetWithPermit`
- Supports ERC-2771 trusted-forwarder context
- Uses a 5% reward fee
- Allows users to claim rewards
- Allows the owner, operator, or trusted forwarder to distribute rewards
- Allows the owner to update the maximum bet and operator
- Allows the owner to withdraw ERC-20 funds from the contract

Constructor arguments:

```solidity
constructor(
    address paymentToken,
    address trustedForwarder,
    address operator
)
```

- `paymentToken` must be the intended BEP-20 betting Token on the selected BSC network.
- Permit-based betting requires the payment Token to implement EIP-2612 Permit.
- `trustedForwarder` is the relayer/forwarder allowed to provide ERC-2771 sender context.
- `operator` is authorized to distribute rewards.
- The deployer becomes the contract owner.

## Important contract considerations

This repository should be independently audited before production use. In particular:

- `settleRound` currently derives the winner from the previous block hash. This is not equivalent to a verifiable random function and may be influenceable by block producers or settlement timing.
- Anyone can call `settleRound` after a round ends.
- The payment Token address is immutable after deployment.
- The trusted forwarder is configured in the constructor and cannot currently be changed.
- `withdrawFunds` allows the owner to transfer ERC-20 assets from the game contract.
- Losing bets and the 5% fee remain in the contract until handled through the owner withdrawal flow.
- Confirm the expected behavior when a winning faction has no bets.
- The default maximum bet assumes an 18-decimal payment Token.
- Owner and operator keys are privileged and must be protected with production-grade key management. A multisig should be considered for ownership.

## Repository layout

```text
src/
  HarryHowardAI.sol       HHA Token
  HourlySquadGame.sol     SquadGame contract
  Counter.sol             Default Foundry example contract

script/
  Deploy.s.sol            Deploy HHA Token
  DeploySquadGame.s.sol   Deploy HourlySquadGame
  GetNonce.s.sol          Display deployer address and nonce
  WithdrawFunds.s.sol     Withdraw payment Tokens from SquadGame
  Counter.s.sol           Default Foundry example script

test/
  HourlySquadGame.t.sol   Permit, operator, owner, and relayer tests
  Counter.t.sol           Default Foundry example tests

broadcast/                Foundry broadcast records
out/                      Compiler output
HourlySquadGame.abi       Exported ABI for Go binding generation
HourlySquadGame.bin       Exported bytecode
HourlySquadGame.go        Generated Go binding
```

## Requirements

Required for normal Solidity development:

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
  - `forge`
  - `cast`
  - `anvil`
- Git with submodule support
- A BSC RPC endpoint
- BNB for deployment and transaction gas
- A BscScan API key for contract verification

Additional tools required only for Go binding generation:

- `jq`
- `abigen` from go-ethereum

Check the installation:

```bash
forge --version
cast --version
anvil --version
jq --version
abigen --version
```

## Clone and install dependencies

The project uses Git submodules for forge-std and OpenZeppelin Contracts.

```bash
git clone --recurse-submodules <repository-url>
cd HowardAI_Token
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

The configured Solidity remappings are stored in `remappings.txt`.

## Environment configuration

Create `.env` in the repository root. It is ignored by Git and must never be committed.

```dotenv
PRIVATE_KEY=<deployer-or-owner-private-key>

BSC_RPC_URL=<BSC-Mainnet-RPC-URL>
BSC_TESTNET_RPC_URL=<BSC-Testnet-RPC-URL>
BSCSCAN_API_KEY=<BscScan-API-key>

PAYMENT_TOKEN_ADDRESS=<BEP-20-payment-token-address>
TRUSTED_FORWARDER=<ERC-2771-trusted-forwarder-address>
OPERATOR_ADDRESS=<SquadGame-operator-address>
```

Configuration details:

- `PRIVATE_KEY` is read by all broadcast scripts. Use a dedicated deployer/owner wallet with only the required BNB and permissions.
- `BSC_RPC_URL` must connect to BSC Mainnet, Chain ID `56`.
- `BSC_TESTNET_RPC_URL` must connect to BSC Testnet, Chain ID `97`.
- `BSCSCAN_API_KEY` is used by verification commands.
- `PAYMENT_TOKEN_ADDRESS` is passed to the SquadGame constructor and used by the withdrawal script.
- `TRUSTED_FORWARDER` and `OPERATOR_ADDRESS` are separate security roles. See the detailed guidance below before deploying.

### Trusted forwarder and operator

`TRUSTED_FORWARDER` is the address of an ERC-2771 forwarder contract, not normally a personal wallet or backend EOA. When the forwarder calls `HourlySquadGame`, the contract trusts the sender information appended to the calldata and uses it as `_msgSender()`. This enables relayed calls such as `placeBet()` and `claimRewards()` while preserving the original user's address. The trusted forwarder is fixed by the constructor and cannot be changed after deployment; changing it requires deploying a new `HourlySquadGame` contract. Set it to the zero address only when ERC-2771 relaying is intentionally disabled.

`OPERATOR_ADDRESS` is the operational account authorized to call `distributeRewards()`. It should normally be a dedicated backend signer, multisig, or other tightly controlled operational address. The owner can rotate it after deployment with `setOperator()`. The Makefile derives an operator from `PRIVATE_KEY` when this variable is not set, but production deployments should always set it explicitly.

The contract technically permits both variables to contain the same address, but that is usually not the correct configuration. A normal EOA must not be configured as the trusted forwarder: direct calls from that address may be interpreted as ERC-2771 forwarded calls, causing `_msgSender()` to be decoded from calldata incorrectly. Reusing one address also combines relaying and reward-distribution privileges. Use the same address only when it is deliberately implemented as both a valid ERC-2771 forwarder contract and the operational reward distributor, and document and audit that design.

Recommended production separation:

| Variable | Expected address type | Purpose | Changeable after deployment |
| --- | --- | --- | --- |
| `TRUSTED_FORWARDER` | Deployed ERC-2771 forwarder contract | Verifies/forwards relayed user calls and preserves the original sender | No; redeploy `HourlySquadGame` |
| `OPERATOR_ADDRESS` | Dedicated backend signer, multisig, or controlled operator account | Calls `distributeRewards()` | Yes; owner calls `setOperator()` |

Never paste a private key directly into a command, commit, issue, terminal screenshot, or chat message. Prefer a hardware wallet, secure signer, encrypted keystore, or CI secret store for production deployments.

## Foundry configuration

`foundry.toml` defines two named RPC endpoints:

```text
bsc          -> BSC_RPC_URL
bsc_testnet  -> BSC_TESTNET_RPC_URL
```

The same names are used by the Makefile and Forge commands.

Verify network selection before broadcasting:

```bash
cast chain-id --rpc-url bsc
cast chain-id --rpc-url bsc_testnet
```

Expected results:

```text
bsc          56
bsc_testnet  97
```

## Build

```bash
forge build
```

Useful build operations:

```bash
forge clean
forge build --sizes
forge inspect HarryHowardAI abi
forge inspect HourlySquadGame abi
```

## Format

Apply Solidity formatting:

```bash
forge fmt
```

Check formatting without changing files:

```bash
forge fmt --check
```

## Test

Run the complete test suite:

```bash
forge test
```

Verbose test output:

```bash
forge test -vvv
```

Run only SquadGame tests:

```bash
forge test --match-path test/HourlySquadGame.t.sol -vvv
```

Run a single test:

```bash
forge test --match-test testPlaceBetWithPermit_Relayed -vvvv
```

Coverage and gas snapshot:

```bash
forge coverage
forge snapshot
```

Tests run locally and do not require a funded wallet unless a fork URL or broadcast option is added.

## Local BSC-compatible development

Start Anvil:

```bash
anvil
```

Anvil is useful for local contract behavior, but it is not BSC. Use a BSC fork when behavior depends on deployed BEP-20 Tokens or BSC state:

```bash
anvil --fork-url "$BSC_TESTNET_RPC_URL"
```

Do not assume that a successful Anvil test guarantees BSC production behavior. Always test the deployment scripts and integrations on BSC Testnet first.

## Deployment workflow

Recommended order:

1. Run formatting and tests.
2. Confirm the target RPC Chain ID.
3. Confirm deployer address and nonce.
4. Simulate the deployment without `--broadcast`.
5. Deploy to BSC Testnet.
6. Verify the Testnet contracts and test frontend/backend integration.
7. Review constructor arguments and privileged addresses again.
8. Deploy to BSC Mainnet.
9. Verify source code on BscScan.
10. Record contract addresses in the backend, frontend, and deployment registry.

Pre-deployment checks:

```bash
forge fmt --check
forge test -vvv
forge build --sizes
make get-nonce-testnet
```

## Deploy the HHA Token

### BSC Testnet

```bash
make deploy-testnet
```

Equivalent Forge command:

```bash
forge script script/Deploy.s.sol:DeployToken \
  --rpc-url bsc_testnet \
  --broadcast
```

### BSC Mainnet

```bash
make deploy-mainnet
```

Equivalent Forge command:

```bash
forge script script/Deploy.s.sol:DeployToken \
  --rpc-url bsc \
  --broadcast
```

The deployer receives the full initial HHA supply and becomes the Token owner.

To simulate before broadcasting, run the same Forge command without `--broadcast`.

## Verify the HHA Token

The existing Make target verifies the Token on BSC Mainnet:

```bash
make verify-token
```

It reads the Token address from the first line of `address.txt`, uses Chain ID `56`, and waits for BscScan verification.

Equivalent command:

```bash
forge verify-contract \
  <HHA_TOKEN_ADDRESS> \
  src/HarryHowardAI.sol:HarryHowardAI \
  --chain-id 56 \
  --watch \
  --etherscan-api-key "$BSCSCAN_API_KEY"
```

Before using `make verify-token`, confirm that line 1 of `address.txt` contains the intended Mainnet Token address.

## Deploy HourlySquadGame

Before deploying, verify all three constructor values:

```text
PAYMENT_TOKEN_ADDRESS
TRUSTED_FORWARDER
OPERATOR_ADDRESS
```

### BSC Testnet

```bash
make deploy-squad-testnet
```

Equivalent Forge command:

```bash
forge script script/DeploySquadGame.s.sol:DeploySquadGame \
  --rpc-url bsc_testnet \
  --broadcast \
  --with-gas-price 5000000000
```

### BSC Mainnet

```bash
make deploy-squad-mainnet
```

Equivalent Forge command:

```bash
forge script script/DeploySquadGame.s.sol:DeploySquadGame \
  --rpc-url bsc \
  --broadcast
```

The deployer becomes the owner. `OPERATOR_ADDRESS` becomes the reward-distribution operator.

## Verify HourlySquadGame

The existing Make target verifies the Mainnet SquadGame contract:

```bash
make verify-squad-mainnet
```

It:

- Reads the contract address from line 7 of `address.txt`.
- Uses Chain ID `56`.
- ABI-encodes `PAYMENT_TOKEN_ADDRESS`, `TRUSTED_FORWARDER`, and `OPERATOR_ADDRESS` as constructor arguments.
- Submits verification to BscScan and waits for completion.

Equivalent command:

```bash
forge verify-contract \
  <SQUAD_GAME_ADDRESS> \
  src/HourlySquadGame.sol:HourlySquadGame \
  --chain-id 56 \
  --watch \
  --etherscan-api-key "$BSCSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode \
    'constructor(address,address,address)' \
    "$PAYMENT_TOKEN_ADDRESS" \
    "$TRUSTED_FORWARDER" \
    "$OPERATOR_ADDRESS")"
```

Constructor arguments must exactly match the deployment transaction or verification will fail.

There is currently no dedicated `verify-squad-testnet` Make target. Use the equivalent command with Chain ID `97` and the Testnet contract address when Testnet verification is required.

## Check deployer nonce

BSC Mainnet:

```bash
make get-nonce-mainnet
```

BSC Testnet:

```bash
make get-nonce-testnet
```

These commands run `script/GetNonce.s.sol:GetNonce`, derive the deployer from `PRIVATE_KEY`, and print its current nonce on the selected network.

## Withdraw SquadGame funds

Only the SquadGame owner can successfully run the withdrawal.

BSC Testnet:

```bash
make withdraw-squad-testnet
```

BSC Mainnet:

```bash
make withdraw-squad-mainnet
```

The withdrawal script:

1. Reads `SQUAD_GAME_ADDRESS` and `PAYMENT_TOKEN_ADDRESS`.
2. Reads the game contract's payment-Token balance.
3. Calls `withdrawFunds(paymentToken, balance)` when the balance is non-zero.
4. Transfers the Tokens to the owner/deployer executing the script.

The existing Makefile derives `SQUAD_GAME_ADDRESS` from fixed lines in `address.txt`:

- Testnet: line 4
- Mainnet: line 10

Review the selected address before every withdrawal. A line-number-based address registry is fragile; replacing it with named environment variables or network-specific deployment files is recommended.

Equivalent direct command:

```bash
SQUAD_GAME_ADDRESS=<SQUAD_GAME_ADDRESS> \
forge script script/WithdrawFunds.s.sol:WithdrawFunds \
  --rpc-url bsc_testnet \
  --broadcast \
  --with-gas-price 5000000000
```

For Mainnet, use `--rpc-url bsc` and omit the Testnet-specific gas-price flag unless intentionally required.

## Read contract state with Cast

Set the contract address for the selected environment:

```bash
export SQUAD_GAME_ADDRESS=<SQUAD_GAME_ADDRESS>
```

Read the current round:

```bash
cast call "$SQUAD_GAME_ADDRESS" \
  "getCurrentRoundId()(uint256)" \
  --rpc-url bsc_testnet
```

Read the current round state:

```bash
cast call "$SQUAD_GAME_ADDRESS" \
  "getRoundState(uint256)(uint256,uint256,uint256[4],bool,bool,uint8,uint256,uint256,bytes32)" \
  0 \
  --rpc-url bsc_testnet
```

Read key configuration:

```bash
cast call "$SQUAD_GAME_ADDRESS" "paymentToken()(address)" --rpc-url bsc_testnet
cast call "$SQUAD_GAME_ADDRESS" "operator()(address)" --rpc-url bsc_testnet
cast call "$SQUAD_GAME_ADDRESS" "owner()(address)" --rpc-url bsc_testnet
cast call "$SQUAD_GAME_ADDRESS" "maxBetAmount()(uint256)" --rpc-url bsc_testnet
```

Replace `bsc_testnet` with `bsc` for Mainnet.

## Generate the Go binding

The backend uses a generated Go binding for `HourlySquadGame`.

```bash
make binding-squad
```

The target performs these steps:

1. Runs `forge build`.
2. Extracts the ABI from `out/HourlySquadGame.sol/HourlySquadGame.json` with `jq`.
3. Extracts deployment bytecode.
4. Runs `abigen` with package name `game` and Go type name `HourlySquadGame`.
5. Writes:
   - `HourlySquadGame.abi`
   - `HourlySquadGame.bin`
   - `HourlySquadGame.go`

After changing the contract ABI:

1. Regenerate the binding.
2. Review the generated diff.
3. Copy or synchronize the binding into the HarryHowardAI backend package that imports it.
4. Run the backend Go test suite.

Do not hand-edit `HourlySquadGame.go`; regenerate it from the Solidity artifact.

## Broadcast records and deployed addresses

Foundry writes transaction records under `broadcast/` when `--broadcast` is used. The repository currently keeps non-local broadcast records while ignoring local Anvil Chain ID `31337` and dry-run output.

Before committing broadcast files:

- Confirm they contain no sensitive environment metadata.
- Confirm the Chain ID and contract address are correct.
- Do not commit `.env` or private keys.
- Keep only records required for deployment traceability.

`address.txt` is used by existing Make targets. Because those targets depend on fixed line numbers, do not reorder or insert lines without updating the Makefile.

Prefer treating `broadcast/<script>/<chain-id>/run-latest.json` or a structured, network-specific deployment registry as the source of truth.

## Make targets

| Command | Network | Operation |
| --- | --- | --- |
| `make deploy-mainnet` | BSC Mainnet | Deploy HHA Token |
| `make deploy-testnet` | BSC Testnet | Deploy HHA Token |
| `make verify-token` | BSC Mainnet | Verify HHA Token from `address.txt` line 1 |
| `make deploy-squad-mainnet` | BSC Mainnet | Deploy HourlySquadGame |
| `make deploy-squad-testnet` | BSC Testnet | Deploy HourlySquadGame |
| `make verify-squad-mainnet` | BSC Mainnet | Verify SquadGame from `address.txt` line 7 |
| `make get-nonce-mainnet` | BSC Mainnet | Print deployer address and nonce |
| `make get-nonce-testnet` | BSC Testnet | Print deployer address and nonce |
| `make withdraw-squad-mainnet` | BSC Mainnet | Withdraw from game address at `address.txt` line 10 |
| `make withdraw-squad-testnet` | BSC Testnet | Withdraw from game address at `address.txt` line 4 |
| `make binding-squad` | Local | Build and generate ABI, bytecode, and Go binding |

## Deployment checklist

- `forge fmt --check` passes.
- `forge test -vvv` passes.
- The target RPC returns Chain ID `56` or `97` as expected.
- The deployer address and nonce are correct.
- The deployer has enough BNB for gas.
- `PAYMENT_TOKEN_ADDRESS` is the intended BEP-20 Token on the selected network.
- The payment Token supports EIP-2612 Permit if Permit-based betting is required.
- `TRUSTED_FORWARDER` is the intended ERC-2771 forwarder.
- `OPERATOR_ADDRESS` is explicitly set and controlled by the backend operator.
- Owner, operator, and forwarder permissions are understood and documented.
- Deployment is simulated before `--broadcast`.
- BSC Testnet integration is completed before Mainnet deployment.
- Source verification succeeds on BscScan.
- Deployed addresses are synchronized with the backend and frontend.
- The Go binding is regenerated after ABI changes.
- Broadcast records and address registries are reviewed before commit.

## Troubleshooting

### `forge` cannot resolve OpenZeppelin or forge-std imports

Initialize submodules and confirm `remappings.txt`:

```bash
git submodule update --init --recursive
forge clean
forge build
```

### Script reports a missing environment variable

Confirm `.env` exists in the repository root and contains every variable used by that script. Do not print `PRIVATE_KEY` while debugging.

### Deployment is targeting the wrong chain

Run `cast chain-id --rpc-url <rpc-name>` before broadcasting. BSC Mainnet must return `56`; BSC Testnet must return `97`.

### BscScan verification fails

Check the Chain ID, contract address, compiler settings, source path, API key, and constructor arguments. SquadGame constructor arguments must match the deployment transaction exactly.

### Permit betting reverts

Confirm that the payment Token implements EIP-2612 Permit and that the signature domain, owner, spender, amount, nonce, deadline, and chain ID are correct.

### Withdrawal fails with an ownership error

`WithdrawFunds.s.sol` broadcasts from `PRIVATE_KEY`. That address must be the current SquadGame owner.

### Go backend binding is stale

Run `make binding-squad`, synchronize the generated binding with the backend, and run the backend tests.
