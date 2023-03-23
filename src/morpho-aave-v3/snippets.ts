import { BigNumber, providers } from "ethers";
import { constants } from "ethers/lib/index";

import { PercentMath, WadRayMath } from "@morpho-labs/ethers-utils/lib/maths";
import { minBN, pow10 } from "@morpho-labs/ethers-utils/lib/utils";
import { AToken__factory, VariableDebtToken__factory } from "@morpho-labs/morpho-ethers-contract";

import { P2PRateComputeParams } from "./types";
import { getContracts, getWeightedAvg, getWeightedRate, zeroFloorSub } from "./utils";

/**
 * This function retrieves the total supply over the Morpho Aave v3
 * markets for both collateral and supply only.
 *
 * @param provider A provider instance
 */
export const getTotalSupply = async (provider: providers.BaseProvider) => {
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
            supply: { scaledDelta, scaledP2PTotal },
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
        WadRayMath.rayMul(scaledP2PTotal, p2pIndex),
        WadRayMath.rayMul(scaledDelta, poolIndex)
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
            borrow: { scaledDelta, scaledP2PTotal },
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
        WadRayMath.rayMul(scaledP2PTotal, p2pIndex),
        WadRayMath.rayMul(scaledDelta, poolIndex)
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
export const getTotalMarketSupply = async (
  underlying: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3 } = getContracts(provider);
  const {
    aToken: aTokenAddress,
    indexes: {
      supply: { p2pIndex, poolIndex },
    },
    deltas: {
      supply: { scaledDelta, scaledP2PTotal },
    },
    idleSupply,
  } = await morphoAaveV3.market(underlying);

  const aToken = AToken__factory.connect(aTokenAddress, provider);

  const poolSupplyAmount = await aToken.balanceOf(morphoAaveV3.address);

  const p2pSupplyAmount = zeroFloorSub(
    WadRayMath.rayMul(scaledP2PTotal, p2pIndex),
    WadRayMath.rayMul(scaledDelta, poolIndex)
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
      borrow: { scaledDelta, scaledP2PTotal },
    },
  } = await morphoAaveV3.market(underlying);

  const aToken = VariableDebtToken__factory.connect(variableDebtToken, provider);

  const poolBorrowAmount = await aToken.balanceOf(morphoAaveV3.address);

  const p2pBorrowAmount = zeroFloorSub(
    WadRayMath.rayMul(scaledP2PTotal, p2pIndex),
    WadRayMath.rayMul(scaledDelta, poolIndex)
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
export const getCurrentSupplyBalanceInOf = async (
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
  const collateral : BigNumber = await morphoAaveV3.collateralBalance(underlying, user)
  return collateral;
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
 * This function retrieves the supply APY of a user on a given market.
 *
 * @param underlying The market to retrieve the supply APY.
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The experienced rate and the total balance of the deposited liquidity on this market.
 */
export const getCurrentUserSupplyRatePerYear = async (
  underlying: string,
  user: string,
  provider: providers.BaseProvider
) => {
  const [{ balanceInP2P, balanceOnPool }, balanceIdle, { p2pSupplyRate, poolSupplyRate }] =
    await Promise.all([
      getCurrentSupplyBalanceInOf(underlying, user, provider),
      getCurrentCollateralBalanceInOf(underlying, user, provider),
      getSupplyRatesPerYear(underlying, provider),
    ]);

  const poolAmount = balanceIdle.add(balanceOnPool);

  return getWeightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, poolAmount);
};

/**
 * This function retrieves the borrow APY of a user on a given market and returns the result.
 *
 * @param underlying The market to retrieve the borrow APY.
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The experienced rate and the total balance of the borrowed liquidity on this market.
 */
export const getCurrentUserBorrowRatePerYear = async (
  underlying: string,
  user: string,
  provider: providers.BaseProvider
) => {
  const [{ balanceOnPool, balanceInP2P }, { p2pBorrowRate, poolBorrowRate }] = await Promise.all([
    getCurrentBorrowBalanceInOf(underlying, user, provider),
    getBorrowRatesPerYear(underlying, provider),
  ]);

  return getWeightedRate(p2pBorrowRate, poolBorrowRate, balanceInP2P, balanceOnPool);
};

/**
 * This function compute the P2P supply rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 * @returns The p2p supply rate per year in _RAY_ units.
 */
export const getP2PSupplyRate = ({
  poolSupplyRatePerYear,
  poolBorrowRatePerYear,
  p2pIndexCursor,
  p2pIndex,
  poolIndex,
  proportionIdle,
  reserveFactor,
  p2pDelta,
  p2pAmount,
}: P2PRateComputeParams) => {
  let p2pSupplyRate;

  if (poolSupplyRatePerYear.gt(poolBorrowRatePerYear)) p2pSupplyRate = poolBorrowRatePerYear;
  else {
    const p2pRate = getWeightedAvg(poolSupplyRatePerYear, poolBorrowRatePerYear, p2pIndexCursor);

    p2pSupplyRate = p2pRate.sub(
      PercentMath.percentMul(p2pRate.sub(poolBorrowRatePerYear), reserveFactor)
    );
  }

  if (p2pDelta.gt(0) && p2pAmount.gt(0)) {
    const proportionDelta = minBN(
      WadRayMath.rayDiv(
        // TODO: use of indexDivUp
        WadRayMath.rayMul(p2pDelta, poolIndex),
        WadRayMath.rayMul(p2pAmount, p2pIndex)
      ),
      WadRayMath.RAY.sub(proportionIdle) // To avoid proportionDelta + proportionIdle > 1 with rounding errors.
    );

    p2pSupplyRate = WadRayMath.rayMul(
      p2pSupplyRate,
      WadRayMath.RAY.sub(proportionDelta).sub(proportionIdle)
    )
      .add(WadRayMath.rayMul(poolSupplyRatePerYear, proportionDelta))
      .add(proportionIdle);
  }

  return p2pSupplyRate;
};

/**
 * This function compute the P2P borrow rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 *
 * @returns The p2p borrow rate per year un _RAY_ units.
 */
export const getP2PBorrowRate = (params: P2PRateComputeParams) => {
  let p2pBorrowRate: BigNumber;
  if (params.poolSupplyRatePerYear.gt(params.poolBorrowRatePerYear)) {
    p2pBorrowRate = params.poolBorrowRatePerYear;
  } else {
    const p2pRate = getWeightedAvg(
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
};

/**
 * This function compute the supply rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the supply APY.
 * @param provider A provider instance
 *
 * @returns The P2P supply rate per year and the pool supply rate per year in _RAY_ units.
 */
export const getSupplyRatesPerYear = async (
  underlying: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3, pool } = getContracts(provider);

  const [
    { currentLiquidityRate, currentVariableBorrowRate },
    {
      idleSupply,
      deltas: {
        supply: { scaledDelta, scaledP2PTotal },
      },
      indexes: {
        supply: { p2pIndex, poolIndex },
      },
      reserveFactor,
      p2pIndexCursor,
    },
  ] = await Promise.all([pool.getReserveData(underlying), morphoAaveV3.market(underlying)]);

  const totalP2PSupplied: BigNumber = WadRayMath.rayMul(
    scaledP2PTotal,
    p2pIndex // TODO: use updated index
  );
  const propIdleSupply = WadRayMath.rayDiv(idleSupply, totalP2PSupplied);

  const p2pSupplyRate = await getP2PSupplyRate({
    poolSupplyRatePerYear: currentLiquidityRate,
    poolBorrowRatePerYear: currentVariableBorrowRate,
    poolIndex,
    p2pIndex,
    proportionIdle: propIdleSupply,
    p2pDelta: scaledDelta,
    p2pAmount: scaledP2PTotal,
    p2pIndexCursor: BigNumber.from(p2pIndexCursor),
    reserveFactor: BigNumber.from(reserveFactor),
  });

  return {
    p2pSupplyRate,
    poolSupplyRate: currentLiquidityRate,
  };
};

/**
 * This function compute the borrow rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the borrow APY.
 * @param provider A provider instance
 *
 * @returns The P2P borrow rate per year and the pool borrow rate per year in _RAY_ units.
 */
export const getBorrowRatesPerYear = async (
  underlying: string,
  provider: providers.BaseProvider
) => {
  const { morphoAaveV3, pool } = getContracts(provider);

  const [
    { currentLiquidityRate, currentVariableBorrowRate },
    {
      deltas: {
        borrow: { scaledDelta, scaledP2PTotal },
      },
      indexes: {
        borrow: { p2pIndex, poolIndex },
      },
      reserveFactor,
      p2pIndexCursor,
    },
  ] = await Promise.all([pool.getReserveData(underlying), morphoAaveV3.market(underlying)]);

  const p2pBorrowRate = await getP2PBorrowRate({
    poolSupplyRatePerYear: currentLiquidityRate,
    poolBorrowRatePerYear: currentVariableBorrowRate,
    poolIndex,
    p2pIndex,
    proportionIdle: constants.Zero,
    p2pDelta: scaledDelta,
    p2pAmount: scaledP2PTotal,
    p2pIndexCursor: BigNumber.from(p2pIndexCursor),
    reserveFactor: BigNumber.from(reserveFactor),
  });
  return {
    p2pBorrowRate,
    poolBorrowRate: currentVariableBorrowRate,
  };
};

/**
 * This function compute the health factor on a specific user and returns the result.
 *
 * @param user The user address.
 * @param provider A provider instance
 *
 * @returns The health factor in _WAD_ units.
 */
export const getUserHealthFactor = async (user: string, provider: providers.BaseProvider) => {
  const { morphoAaveV3 } = getContracts(provider);
  const { debt, maxDebt } = await morphoAaveV3.liquidityData(user);

  return WadRayMath.wadDiv(maxDebt, debt);
};
