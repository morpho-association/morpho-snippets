import { BigNumber, providers } from "ethers";
import { constants } from "ethers/lib/index";

import { PercentMath } from "@morpho-labs/ethers-utils/lib/maths";
import { maxBN } from "@morpho-labs/ethers-utils/lib/utils";
import { AavePriceOracle__factory, AaveV3Pool__factory } from "@morpho-labs/morpho-ethers-contract";

import { MorphoAaveV3__factory } from "./contracts/MorphoAaveV3__factory";

export const getContracts = (provider: providers.BaseProvider) => ({
  morphoAaveV3: MorphoAaveV3__factory.connect("", provider),
  oracle: AavePriceOracle__factory.connect("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", provider),
  pool: AaveV3Pool__factory.connect("", provider),
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
 * TODO: move it to ethers-utils
 * This function is subtracting one number from another, but ensuring that the result is never negative, instead of returning a negative value it will return zero.
 *
 * @param a A BigNumber.
 * @param b A BigNumber.
 * @returns A non negative number or 0.
 */
export const zeroFloorSub = (a: BigNumber, b: BigNumber) => maxBN(constants.Zero, a.sub(b));
