import { BigNumber, ethers, providers } from "ethers";
import { constants } from "ethers/lib/index";

import { WadRayMath } from "@morpho-labs/ethers-utils/lib/maths";
import { pow10 } from "@morpho-labs/ethers-utils/lib/utils";
import { AToken__factory, VariableDebtToken__factory } from "@morpho-labs/morpho-ethers-contract";

import { getContracts, zeroFloorSub } from "./utils";

/**
 * This function is computing an average rate
 * and returns the weighted rate and the total balance.
 *
 * @param p2pRate The peer-to-peer rate per year, in _RAY_ units
 * @param poolRate The pool rate per year, in _RAY_ units
 * @param balanceInP2P The underlying balance matched peer-to-peer
 * @param balanceOnPool The underlying balance on the pool
 */
export const getWeightedRate = async (
  p2pRate: BigNumber,
  poolRate: BigNumber,
  balanceInP2P: BigNumber,
  balanceOnPool: BigNumber
) => {
  const totalBalance: BigNumber = balanceInP2P.add(balanceOnPool);
  if (totalBalance.isZero())
    return {
      weightedRate: constants.Zero,
      totalBalance,
    };
  return {
    weightedRate: p2pRate.mul(balanceInP2P).add(poolRate.mul(balanceOnPool)).div(totalBalance),
    totalBalance,
  };
};

/// FUNCTIONS

/**
 * This function retrieves the total supply over the Morpho Aave v3
 * markets for both collateral and supply only.
 *
 * @param provider A provider instance
 */
const getTotalSupply = async (provider: providers.BaseProvider) => {
  const { oracle, morphoAaveV3 } = getContracts(provider);
  const markets = await morphoAaveV3.marketsCreated();
  const marketsData = await Promise.all(
    markets.map(async (underlying) => {
      const [
        {
          aToken: aTokenAddress,
          indexes: {
            supply: { p2pIndex, poolIndex },
          },
          deltas: {
            supply: { scaledDeltaPool, scaledTotalP2P },
          },
          idleSupply,
        },
        underlyingPrice,
      ] = await Promise.all([
        morphoAaveV3.market(underlying),
        oracle.getAssetPrice(underlying), // TODO: handle if emode
      ]);

      const aToken = AToken__factory.connect(aTokenAddress, provider);

      const [decimals, poolSupplyAmount] = await Promise.all([
        aToken.decimals(),
        aToken.balanceOf(morphoAaveV3.address),
      ]);

      const p2pSupplyAmount = zeroFloorSub(
        WadRayMath.rayMul(scaledTotalP2P, p2pIndex),
        WadRayMath.rayMul(scaledDeltaPool, poolIndex)
      );

      return {
        p2pSupplyAmount,
        poolSupplyAmount,
        idleSupply,
        underlyingPrice,
        decimals,
      };
    })
  );

  const amounts = marketsData.reduce(
    (acc, { p2pSupplyAmount, poolSupplyAmount, idleSupply, underlyingPrice, decimals }) => {
      const toUsd = (amount: BigNumber) => amount.mul(underlyingPrice).div(pow10(decimals));
      return {
        p2pSupplyAmount: acc.p2pSupplyAmount.add(toUsd(p2pSupplyAmount)),
        poolSupplyAmount: acc.poolSupplyAmount.add(toUsd(poolSupplyAmount)),
        idleSupply: acc.idleSupply.add(toUsd(idleSupply)),
      };
    },
    {
      p2pSupplyAmount: constants.Zero,
      poolSupplyAmount: constants.Zero,
      idleSupply: constants.Zero,
    }
  );

  return {
    ...amounts,
    totalSupplyAmount: amounts.poolSupplyAmount.add(amounts.p2pSupplyAmount),
    markets: marketsData,
  };
};

/**
 * This function retrieves the total borrow over the Morpho Aave v3
 *
 * @param provider A provider instance
 */
export const getTotalBorrow = async (provider: providers.BaseProvider) => {
  const { oracle, morphoAaveV3 } = getContracts(provider);
  const markets = await morphoAaveV3.marketsCreated();

  const marketsData = await Promise.all(
    markets.map(async (underlying) => {
      const [
        {
          variableDebtToken,
          indexes: {
            borrow: { p2pIndex, poolIndex },
          },
          deltas: {
            borrow: { scaledDeltaPool, scaledTotalP2P },
          },
        },
        underlyingPrice,
      ] = await Promise.all([
        morphoAaveV3.market(underlying),
        oracle.getAssetPrice(underlying), // TODO: handle if emode
      ]);

      const debtToken = VariableDebtToken__factory.connect(variableDebtToken, provider);

      const [decimals, poolBorrowAmount] = await Promise.all([
        debtToken.decimals(),
        debtToken.balanceOf(morphoAaveV3.address),
      ]);

      const p2pBorrowAmount = zeroFloorSub(
        WadRayMath.rayMul(scaledTotalP2P, p2pIndex),
        WadRayMath.rayMul(scaledDeltaPool, poolIndex)
      );

      return {
        p2pBorrowAmount,
        poolBorrowAmount,
        underlyingPrice,
        decimals,
      };
    })
  );

  const amounts = marketsData.reduce(
    (acc, { p2pBorrowAmount, poolBorrowAmount, underlyingPrice, decimals }) => {
      const toUsd = (amount: BigNumber) => amount.mul(underlyingPrice).div(pow10(decimals));
      return {
        p2pBorrowAmount: acc.p2pBorrowAmount.add(toUsd(p2pBorrowAmount)),
        poolBorrowAmount: acc.poolBorrowAmount.add(toUsd(poolBorrowAmount)),
      };
    },
    {
      p2pBorrowAmount: constants.Zero,
      poolBorrowAmount: constants.Zero,
    }
  );

  return {
    ...amounts,
    totalSupplyAmount: amounts.poolBorrowAmount.add(amounts.p2pBorrowAmount),
    markets: marketsData,
  };
};

/**
 * This function gets the total supply for one given market.
 *
 * @param underlying The address of the underlying token
 * @param provider A provider instance
 */
const getTotalMarketSupply = async (underlying: string, provider: providers.BaseProvider) => {
  const { morphoAaveV3 } = getContracts(provider);
  const {
    aToken: aTokenAddress,
    indexes: {
      supply: { p2pIndex, poolIndex },
    },
    deltas: {
      supply: { scaledDeltaPool, scaledTotalP2P },
    },
    idleSupply,
  } = await morphoAaveV3.market(underlying);

  const aToken = AToken__factory.connect(aTokenAddress, provider);

  const poolSupplyAmount = await aToken.balanceOf(morphoAaveV3.address);

  const p2pSupplyAmount = zeroFloorSub(
    WadRayMath.rayMul(scaledTotalP2P, p2pIndex),
    WadRayMath.rayMul(scaledDeltaPool, poolIndex)
  );
  return {
    p2pSupplyAmount,
    poolSupplyAmount,
    idleSupply,
    totalSupplyAmount: p2pSupplyAmount.add(poolSupplyAmount).add(idleSupply),
  };
};

/**
 * This function gets the total borrow for one given market.
 *
 * @param underlying The address of the underlying token
 * @param provider A provider instance
 */
export const getTotalMarketBorrow = async (
  underlying: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3 } = getContracts(provider);

  const {
    variableDebtToken,
    indexes: {
      borrow: { p2pIndex, poolIndex },
    },
    deltas: {
      borrow: { scaledDeltaPool, scaledTotalP2P },
    },
  } = await morphoAaveV3.market(underlying);

  const aToken = VariableDebtToken__factory.connect(variableDebtToken, provider);

  const poolBorrowAmount = await aToken.balanceOf(morphoAaveV3.address);

  const p2pBorrowAmount = zeroFloorSub(
    WadRayMath.rayMul(scaledTotalP2P, p2pIndex),
    WadRayMath.rayMul(scaledDeltaPool, poolIndex)
  );

  return {
    p2pBorrowAmount,
    poolBorrowAmount,
    totalBorrowAmount: p2pBorrowAmount.add(poolBorrowAmount),
  };
};

/**
 * This function retrieves the supply balance of one given user in one given market.
 *
 * @param underlying The market to retrieve the supplied liquidity.
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The matched peer-to-peer amount, the pool amount and the total supply amount.
 */
const getCurrentSupplyBalanceInOf = async (
  underlying: string,
  user: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3 } = getContracts(provider);

  const [
    {
      supply: { p2pIndex, poolIndex },
    },
    scaledP2PSupplyBalance,
    scaledPoolSupplyBalance,
  ] = await Promise.all([
    morphoAaveV3.updatedIndexes(underlying),
    morphoAaveV3.scaledP2PSupplyBalance(underlying, user),
    morphoAaveV3.scaledPoolSupplyBalance(underlying, user),
  ]);

  const balanceInP2P = WadRayMath.rayMul(scaledP2PSupplyBalance, p2pIndex);
  const balanceOnPool = WadRayMath.rayMul(scaledPoolSupplyBalance, poolIndex);

  return {
    balanceInP2P,
    balanceOnPool,
    totalBalance: balanceInP2P.add(balanceOnPool),
  };
};

/**
 * This function retrieves the collateral balance of one given user in one given market.
 *
 * @param underlying The market to retrieve the collateral amount.
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The total collateral of the user.
 */
export const getCurrentCollateralBalanceInOf = async (
  underlying: string,
  user: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3 } = getContracts(provider);

  const [
    {
      supply: { poolIndex },
    },
    scaledCollateral,
  ] = await Promise.all([
    morphoAaveV3.updatedIndexes(underlying),
    morphoAaveV3.collateralBalance(underlying, user),
  ]);

  return WadRayMath.rayMul(scaledCollateral, poolIndex);
};

/**
 * This function retrieves the borrow balance of one given user in one given market.
 *
 * @param underlying The market to retrieve the borrowed liquidity.
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The matched peer-to-peer amount, the pool amount and the total borrow amount.
 */
export const getCurrentBorrowBalanceInOf = async (
  underlying: string,
  user: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3 } = getContracts(provider);

  const [
    {
      borrow: { p2pIndex, poolIndex },
    },
    scaledP2PSupplyBalance,
    scaledPoolSupplyBalance,
  ] = await Promise.all([
    morphoAaveV3.updatedIndexes(underlying),
    morphoAaveV3.scaledP2PBorrowBalance(underlying, user),
    morphoAaveV3.scaledPoolBorrowBalance(underlying, user),
  ]);

  const balanceInP2P = WadRayMath.rayMul(scaledP2PSupplyBalance, p2pIndex);
  const balanceOnPool = WadRayMath.rayMul(scaledPoolSupplyBalance, poolIndex);

  return {
    balanceInP2P,
    balanceOnPool,
    totalBalance: balanceInP2P.add(balanceOnPool),
  };
};

/**
 * This function retrieves the supply APY of a user on a given market and returns the result.
 *
 * @param underlying The market to retrieve the supply APY.
 * @param user The user address.
 * @returns The experienced rate and the total balance of the deposited liquidity on this market.
 */
async function getCurrentUserSupplyRatePerYear(underlying: string, user: string) {
  const [balanceInP2P, balanceOnPool] = await getCurrentSupplyBalanceInOf(underlying, user);
  const balanceIdle = await getCurrentCollateralBalanceInOf(underlying, user);
  const poolAmount: BigNumber = balanceIdle.add(balanceOnPool);
  const [p2pSupplyRate, poolSupplyRate] = await getSupplyRatesPerYear(underlying);
  return await getWeightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, poolAmount);
}

/**
 * This function retrieves the borrow APY of a user on a given market and returns the result.
 *
 * @param underlying The market to retrieve the borrow APY.
 * @param user The user address.
 * @returns The experienced rate and the total balance of the borrowed liquidity on this market.
 */
async function getCurrentUserBorrowRatePerYear(
  underlying: string,
  user: string
): Promise<[BigNumber, BigNumber]> {
  const [balanceInP2P, balanceOnPool] = await getCurrentBorrowBalanceInOf(underlying, user);
  const [p2pSupplyRate, poolSupplyRate] = await getBorrowRatesPerYear(underlying);
  return await getWeightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, balanceOnPool);
}

/**
 * This function compute the P2P supply rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 * @returns The p2p supply rate.
 */
async function getP2PSupplyRate(params: P2PRateComputeParams): Promise<BigNumber> {
  let p2pSupplyRate: BigNumber;
  if (params.poolSupplyRatePerYear.gt(params.poolBorrowRatePerYear)) {
    p2pSupplyRate = params.poolBorrowRatePerYear;
  } else {
    const p2pRate = await getWeightedAvg(
      params.poolSupplyRatePerYear,
      params.poolBorrowRatePerYear,
      params.p2pIndexCursor
    );

    p2pSupplyRate = p2pRate.sub(
      p2pRate.sub(params.poolSupplyRatePerYear).mul(params.reserveFactor).div(WadRayMath.RAY)
    );
  }
  if (params.p2pDelta.gt(0) && params.p2pAmount.gt(0)) {
    const a = params.p2pDelta.mul(params.poolIndex).div(params.p2pAmount.mul(params.p2pIndex));
    const b = WadRayMath.RAY;
    const shareOfTheDelta = a.gt(b) ? b : a;
    p2pSupplyRate = p2pSupplyRate
      .mul(WadRayMath.RAY.sub(shareOfTheDelta).sub(params.proportionIdle))
      .div(WadRayMath.RAY)
      .add(params.poolSupplyRatePerYear.mul(shareOfTheDelta).div(WadRayMath.RAY));
  }
  return p2pSupplyRate;
}

/**
 * This function compute the P2P borrow rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 * @returns The p2p borrow rate.
 */
async function getP2PBorrowRate(params: P2PRateComputeParams): Promise<BigNumber> {
  let p2pBorrowRate: BigNumber;
  if (params.poolSupplyRatePerYear.gt(params.poolBorrowRatePerYear)) {
    p2pBorrowRate = params.poolBorrowRatePerYear;
  } else {
    const p2pRate = await getWeightedAvg(
      params.poolSupplyRatePerYear,
      params.poolBorrowRatePerYear,
      params.p2pIndexCursor
    );

    p2pBorrowRate = p2pRate.sub(
      p2pRate.sub(params.poolBorrowRatePerYear).mul(params.reserveFactor).div(WadRayMath.RAY)
    );
  }
  if (params.p2pDelta.gt(0) && params.p2pAmount.gt(0)) {
    const a = params.p2pDelta.mul(params.poolIndex).div(params.p2pAmount.mul(params.p2pIndex));
    const b = WadRayMath.RAY;
    const shareOfTheDelta = a.gt(b) ? b : a;
    p2pBorrowRate = p2pBorrowRate
      .mul(WadRayMath.RAY.sub(shareOfTheDelta))
      .div(WadRayMath.RAY)
      .add(params.poolBorrowRatePerYear.mul(shareOfTheDelta).div(WadRayMath.RAY));
  }
  return p2pBorrowRate;
}

/**
 * This function compute the supply rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the supply APY.
 * @returns The P2P supply rate and the pool supply rate.
 */
async function getSupplyRatesPerYear(underlying): Promise<[BigNumber, BigNumber]> {
  const reserve = await pool.getReserveData(underlying);
  const market = await morpho.market(underlying);

  const idleSupply: BigNumber = market.idleSupply;
  const totalP2PSupplied: BigNumber = WadRayMath.rayMul(
    market.deltas.supply.scaledP2PTotal,
    market.indexes.supply.p2pIndex
  );
  const propIdleSupply = WadRayMath.rayDiv(idleSupply, totalP2PSupplied);

  const params: P2PRateComputeParams = {
    poolSupplyRatePerYear: reserve.currentLiquidityRate,
    poolBorrowRatePerYear: reserve.currentVariableBorrowRate,
    poolIndex: market.indexes.supply.poolIndex,
    p2pIndex: market.indexes.supply.p2pIndex,
    proportionIdle: propIdleSupply,
    p2pDelta: market.deltas.supply.scaledDelta,
    p2pAmount: market.deltas.supply.scaledP2PTotal,
    p2pIndexCursor: market.p2pIndexCursor,
    reserveFactor: market.reserveFactor,
  };

  const P2PSupplyRate = await getP2PSupplyRate(params);
  return [P2PSupplyRate, params.poolSupplyRatePerYear];
}

/**
 * This function compute the borrow rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the borrow APY.
 * @returns The P2P borrow rate and the pool borrow rate.
 */
async function getBorrowRatesPerYear(underlying): Promise<[BigNumber, BigNumber]> {
  const reserve = await pool.getReserveData(underlying);
  const market = await morpho.market(underlying);
  const totalP2PBorrowed: BigNumber = WadRayMath.rayMul(
    market.deltas.borrow.scaledP2PTotal,
    market.indexes.borrow.p2pIndex
  );

  const params: P2PRateComputeParams = {
    poolSupplyRatePerYear: reserve.currentLiquidityRate,
    poolBorrowRatePerYear: reserve.currentVariableBorrowRate,
    poolIndex: market.indexes.borrow.poolIndex,
    p2pIndex: market.indexes.borrow.p2pIndex,
    proportionIdle: BigNumber.from(0),
    p2pDelta: market.deltas.borrow.scaledDelta,
    p2pAmount: market.deltas.borrow.scaledP2PTotal,
    p2pIndexCursor: market.p2pIndexCursor,
    reserveFactor: market.reserveFactor,
  };

  const P2PBorrowRate = await getP2PBorrowRate(params);
  return [P2PBorrowRate, params.poolBorrowRatePerYear];
}

/**
 * This function compute the health factor on a specific user and returns the result.
 *
 * @param user The user address.
 * @returns The health factor.
 */
async function getUserHealthFactor(user: string): Promise<BigNumber> {
  const liquidityData: LiquidityData = await morpho.liquidityData(user);
  const healthFactor = WadRayMath.rayDiv(liquidityData.maxDebt, liquidityData.debt);
  return healthFactor;
}
