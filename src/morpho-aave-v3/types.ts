import { BigNumber } from "ethers";

export interface P2PRateComputeParams {
  /** The pool supply rate per year (in ray). */
  poolSupplyRatePerYear: BigNumber;

  /** The pool borrow rate per year (in ray). */
  poolBorrowRatePerYear: BigNumber;

  /** The last stored pool index (in ray). */
  poolIndex: BigNumber;

  /** The last stored peer-to-peer index (in ray). */
  p2pIndex: BigNumber;

  /**  The delta amount in pool unit. */
  p2pDelta: BigNumber;

  /**  The total peer-to-peer amount in peer-to-peer unit. */
  p2pAmount: BigNumber;

  /** The index cursor of the given market (in bps). */
  p2pIndexCursor: BigNumber;

  /** The reserve factor of the given market (in bps). */
  reserveFactor: BigNumber;

  /** The proportion idle of the given market (in underlying). */
  proportionIdle: BigNumber;
}
