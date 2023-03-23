import { BigNumber } from "ethers";

export interface P2PRateComputeParams {
  poolSupplyRatePerYear: BigNumber;
  poolBorrowRatePerYear: BigNumber;
  poolIndex: BigNumber;
  p2pIndex: BigNumber;
  proportionIdle: BigNumber;
  p2pDelta: BigNumber;
  p2pAmount: BigNumber;
  p2pIndexCursor: BigNumber;
  reserveFactor: BigNumber;
}
