import { BigNumber, providers } from "ethers";
import { constants } from "ethers/lib/index";

import { PercentMath } from "@morpho-labs/ethers-utils/lib/maths";
import { maxBN } from "@morpho-labs/ethers-utils/lib/utils";
import { AavePriceOracle__factory, AaveV3Pool__factory } from "@morpho-labs/morpho-ethers-contract";

import { MorphoAaveV3__factory } from "../contracts";

export const getContracts = (provider: providers.BaseProvider) => ({
  morphoAaveV3: MorphoAaveV3__factory.connect("0x123123", provider),
  oracle: AavePriceOracle__factory.connect("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", provider),
  pool: AaveV3Pool__factory.connect("0x123123", provider),
});

/**
 * This function Executes a weighted average (x * (1 - p) + y * p), rounded up and returns the result.
 * TODO: move it to ethers-utils
 *
 * @param x The first value, with a weight of 1 - percentage.
 * @param y The second value, with a weight of percentage.
 * @param percentage The weight of y, and complement of the weight of x.
 * @returns The result of the weighted average.
 */
export const getWeightedAvg = (x: BigNumber, y: BigNumber, percentage: BigNumber) => {
  const MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR = constants.MaxUint256.sub(
    PercentMath.HALF_PERCENT
  );
  let z: BigNumber = PercentMath.BASE_PERCENT.sub(percentage);

  if (
    percentage.gt(PercentMath.BASE_PERCENT) ||
    (percentage.gt(0) && y.gt(MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR.div(percentage))) ||
    (PercentMath.BASE_PERCENT.gt(percentage) &&
      x.gt(MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR.sub(y.mul(percentage)).div(z)))
  ) {
    throw new Error("Underflow or overflow detected");
  }

  z = x.mul(z).add(y.mul(percentage)).add(PercentMath.HALF_PERCENT).div(PercentMath.BASE_PERCENT);

  return z;
};


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


/**
 * TODO: move it to ethers-utils
 * This function is subtracting one number from another, but ensuring that the result is never negative, instead of returning a negative value it will return zero.
 *
 * @param a A BigNumber.
 * @param b A BigNumber.
 * @returns A non negative number or 0.
 */
export const zeroFloorSub = (a: BigNumber, b: BigNumber) => maxBN(constants.Zero, a.sub(b));
