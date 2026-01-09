-include .env

.PHONY: deploy verify

deploy:
	forge script script/Deploy.s.sol:DeployToken --rpc-url $(BSC_RPC_URL) --broadcast

verify:
	forge verify-contract $(shell head -n 1 address.txt) src/HarryHowardAI.sol:HarryHowardAI --chain-id 56 --watch --etherscan-api-key $(BSCSCAN_API_KEY)
