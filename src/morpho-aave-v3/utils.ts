import { BigNumber, providers } from "ethers";

import { AavePriceOracle__factory, AaveV3Pool__factory } from "@morpho-labs/morpho-ethers-contract";

import { MorphoAaveV3__factory } from "./contracts/MorphoAaveV3__factory";

export const getContracts = (provider: providers.BaseProvider) => ({
  morphoAaveV3: MorphoAaveV3__factory.connect("", provider),
  oracle: AavePriceOracle__factory.connect("0xA50ba011c48153De246E5192C8f9258A2ba79Ca9", provider),
  pool: AaveV3Pool__factory.connect("", provider),
});

/**
 * TODO: move it to ethers-utils
 * This function is subtracting one number from another, but ensuring that the result is never negative, instead of returning a negative value it will return zero.
 *
 * @param a A BigNumber.
 * @param b A BigNumber.
 * @returns A non negative number or 0.
 */
function zeroFloorSub(a: BigNumber, b: BigNumber): BigNumber {
  return b.gt(a) ? BigNumber.from("0") : a.sub(b);
}
