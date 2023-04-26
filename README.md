# Morpho-snippets

## Typescript & Solidity based snippets related to Morpho Protocols.

## IMPORTANT

This repository contains smart contracts that have been developed for educational, experimental, or demonstration purposes only. By using or interacting with these smart contracts, you acknowledge and accept the following:

- The smart contracts in this repository have not been audited and are provided "as is" with no guarantees, warranties, or assurances of any kind. The authors and maintainers of this repository are not responsible for any damages, losses, or liabilities that may arise from the use or deployment of these smart contracts.

- The smart contracts in this repository are not intended for use in production environments or for the management of real-world assets, funds, or resources. Any use or deployment of these smart contracts for such purposes is done entirely at your own risk.

- The smart contracts are provided for reference and learning purposes, and you are solely responsible for understanding, modifying, and deploying them as needed.

### Morpho-Aave-V3 related functions, in Typescript.

One can use one of the following functions to get relevant data:

- getTotalSupply
- getTotalBorrow

- getTotalMarketSupply
- getTotalMarketBorrow

- getCurrentSupplyBalanceInOf
- getCurrentCollateralBalanceInOf
- getCurrentBorrowBalanceInOf

- getCurrentUserSupplyRatePerYear
- getCurrentUserBorrowRatePerYear

- getP2PSupplyRate
- getP2PBorrowRate

- getSupplyRatesPerYear
- getBorrowRatesPerYear

- getUserHealthFactor

### Morpho-Aave-V3 related functions in Solidity.

One can use the following snippets to get relevant data:

- totalSupply
- totalBorrow

- supplyAPR
- borrowAPR
- avgBorrowAPR

- healthFactor

- marketSupply
- marketBorrow

- supplyBalance
- borrowBalance

- poolAPR
- assetPrice

The Utils library gathers some pieces of code used in the snippets. You can also visit the [MorphoGetters.sol](https://github.com/morpho-dao/morpho-aave-v3/src/MorphoGetters.sol) file to have a look at all the data available from the Morpho Contract.

### Getting Started

- Install [Foundry](https://github.com/foundry-rs/foundry).
- Install yarn
- Run foundryup
- Run forge install
- Create a `.env` file according to the [`.env.example`](./.env.example) file.

### Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a fork of real networks, which allows us to interact directly with liquidity pools of Aave V3. Note that you need to have an RPC provider that have access to Ethereum.

You can run the test by running the command: `forge test`

### VSCode setup

Configure your VSCode to automatically format a file on save, using `forge fmt`:

- Install [emeraldwalk.runonsave](https://marketplace.visualstudio.com/items?itemName=emeraldwalk.RunOnSave)
- Update your `settings.json`:

```json
{
  "[solidity]": {
    "editor.formatOnSave": false
  },
  "emeraldwalk.runonsave": {
    "commands": [
      {
        "match": ".sol",
        "isAsync": true,
        "cmd": "forge fmt ${file}"
      }
    ]
  }
}
```

## Questions & Feedback

For any question or feedback you can send an email to [merlin@morpho.xyz](mailto:merlin@morpho.xyz).

---

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).
