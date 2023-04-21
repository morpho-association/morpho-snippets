# Morpho-snippets

## Typescript based snippets related to Morpho Protocols.

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

- userHealthFactor

- marketSupply
- marketBorrow

- supplyBalance
- borrowBalance

- poolAPR
- assetPrice

The Utils library gathers some pieces of code used in the snippets. You can also visit the morphoGetters.sol file to have a look at all the data available from the Morpho Contract.

### Getting Started

- Install [Foundry](https://github.com/foundry-rs/foundry).
- Install yarn
- Run foundryup
- Run forge install
- Create a `.env` file according to the [`.env.example`](./.env.example) file.

### Testing with [Foundry](https://github.com/foundry-rs/foundry) 🔨

Tests are run against a fork of real networks, which allows us to interact directly with liquidity pools of AaveV3. Note that you need to have an RPC provider that have access to Ethereum or Avalanche.

You can run the test by running the command : forge test 


## Questions & Feedback

For any question or feedback you can send an email to [merlin@morpho.xyz].

---

## Licensing

The code is under the GNU AFFERO GENERAL PUBLIC LICENSE v3.0, see [`LICENSE`](./LICENSE).
