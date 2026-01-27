-include .env

.PHONY: deploy-mainnet deploy-testnet verify binding-squad

deploy-mainnet:
	forge script script/Deploy.s.sol:DeployToken --rpc-url bsc --broadcast

deploy-testnet:
	forge script script/Deploy.s.sol:DeployToken --rpc-url bsc_testnet --broadcast

verify-token:
	forge verify-contract $(shell head -n 1 address.txt) src/HarryHowardAI.sol:HarryHowardAI --chain-id 56 --watch --etherscan-api-key $(BSCSCAN_API_KEY)

deploy-squad-mainnet:
	forge script script/DeploySquadGame.s.sol:DeploySquadGame --rpc-url bsc --broadcast

deploy-squad-testnet:
	forge script script/DeploySquadGame.s.sol:DeploySquadGame --rpc-url bsc_testnet --broadcast

get-nonce-mainnet:
	forge script script/GetNonce.s.sol:GetNonce --rpc-url bsc

get-nonce-testnet:
	forge script script/GetNonce.s.sol:GetNonce --rpc-url bsc_testnet

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
