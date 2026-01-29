-include .env

.PHONY: deploy-mainnet deploy-testnet verify binding-squad

deploy-mainnet:
	forge script script/Deploy.s.sol:DeployToken --rpc-url bsc --broadcast

deploy-testnet:
	forge script script/Deploy.s.sol:DeployToken --rpc-url bsc_testnet --broadcast

verify-token:
	forge verify-contract $(shell head -n 1 address.txt) src/HarryHowardAI.sol:HarryHowardAI --chain-id 56 --watch --etherscan-api-key $(BSCSCAN_API_KEY)

# Default Operator to Deployer if not set
OPERATOR_ADDRESS ?= $(shell cast wallet address --private-key $(PRIVATE_KEY))

verify-squad-mainnet:
	forge verify-contract $(shell sed -n '7p' address.txt) src/HourlySquadGame.sol:HourlySquadGame --chain-id 56 --watch --etherscan-api-key $(BSCSCAN_API_KEY) --constructor-args $(shell cast abi-encode "constructor(address,address,address)" $(PAYMENT_TOKEN_ADDRESS) $(TRUSTED_FORWARDER) $(OPERATOR_ADDRESS))

deploy-squad-mainnet:
	forge script script/DeploySquadGame.s.sol:DeploySquadGame --rpc-url bsc --broadcast

deploy-squad-testnet:
	forge script script/DeploySquadGame.s.sol:DeploySquadGame --rpc-url bsc_testnet --broadcast --with-gas-price 5000000000

get-nonce-mainnet:
	forge script script/GetNonce.s.sol:GetNonce --rpc-url bsc

get-nonce-testnet:
	forge script script/GetNonce.s.sol:GetNonce --rpc-url bsc_testnet

withdraw-squad-mainnet:
	SQUAD_GAME_ADDRESS=$(shell sed -n '10p' address.txt) forge script script/WithdrawFunds.s.sol:WithdrawFunds --rpc-url bsc --broadcast

withdraw-squad-testnet:
	SQUAD_GAME_ADDRESS=$(shell sed -n '4p' address.txt) forge script script/WithdrawFunds.s.sol:WithdrawFunds --rpc-url bsc_testnet --broadcast --with-gas-price 5000000000

# 生成 Go Binding
binding-squad:
	@echo "Building contracts..."
	@forge build
	@echo "Extracting ABI..."
	@cat out/HourlySquadGame.sol/HourlySquadGame.json | jq .abi > HourlySquadGame.abi
	@echo "Extracting Bytecode..."
	@cat out/HourlySquadGame.sol/HourlySquadGame.json | jq -r .bytecode.object > HourlySquadGame.bin
	@echo "Generating Go bindings..."
	@abigen --bin=HourlySquadGame.bin --abi=HourlySquadGame.abi --pkg=game --type=HourlySquadGame --out=HourlySquadGame.go
	@echo "Done! Generated HourlySquadGame.go"
