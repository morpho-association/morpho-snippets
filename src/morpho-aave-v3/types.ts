import {BigNumber} from "ethers";

export interface LiquidityData {
    borrowable: BigNumber;
    maxDebt: BigNumber;
    debt: BigNumber;
}

export interface MarketSideDelta {
    scaledDelta: BigNumber;
    scaledP2PTotal: BigNumber;
}

export interface Deltas {
    supply: MarketSideDelta;
    borrow: MarketSideDelta;
}

export interface MarketSideIndexes {
    poolIndex: BigNumber;
    p2pIndex: BigNumber;
}

export interface Indexes {
    supply: MarketSideIndexes;
    borrow: MarketSideIndexes;
}

export interface PauseStatuses {
    underlyingPaused: boolean;
    depositPaused: boolean;
    borrowPaused: boolean;
}

export interface Market {
    indexes: Indexes;
    deltas: Deltas;
    underlying: string;
    pauseStatuses: PauseStatuses;
    variableDebtToken: string;
    lastUpdateTimestamp: number;
    reserveFactor: BigNumber;
    p2pIndexCursor: BigNumber;
    aToken: string;
    stableDebtToken: string;
    idleSupply: BigNumber;
}

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