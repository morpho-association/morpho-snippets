import {BigNumber, ethers} from "ethers";
import * as dotenv from "dotenv";
import * as MorphoAbi from "../abis/MorphoAbi.json";
import { WadRayMath } from "@morpho-labs/ethers-utils/lib/maths";
dotenv.config();


/// CONTRACTS
const morpho = new ethers.Contract(
  // New Morpho Address
  "XXX",
  MorphoAbi,
  signer
);
const oracle = new ethers.Contract(
  "0xA50ba011c48153De246E5192C8f9258A2ba79Ca9",
  OracleAbi,
  signer
);

const pool = new ethers.Contract(
  // pool Address
  "XXX",
  PoolAbi,
  signer
);


/// INTERFACES
interface LiquidityData {
  borrowable: BigNumber;
  maxDebt: BigNumber;
  debt: BigNumber;
}

interface MarketSideDelta {
  scaledDelta: BigNumber;
  scaledP2PTotal: BigNumber;
}

interface Deltas {
  supply: MarketSideDelta;
  borrow: MarketSideDelta;
}

interface MarketSideIndexes {
  poolIndex: BigNumber;
  p2pIndex: BigNumber;
}

interface Indexes {
  supply: MarketSideIndexes;
  borrow: MarketSideIndexes;
}

interface PauseStatuses {
  underlyingPaused: boolean;
  depositPaused: boolean;
  borrowPaused: boolean;
}

interface Market {
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

interface P2PRateComputeParams {
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

/// UTILS
/**
 * This function is subtracting one number from another, but ensuring that the result is never negative, instead of returning a negative value it will return zero.
 *
 * @param a A BigNumber.
 * @param b A BigNumber.
 * @returns A non negative number or 0.
 */
function zeroFloorSub(a: BigNumber, b: BigNumber): BigNumber {
  return b.gt(a) ? BigNumber.from("0") : a.sub(b);
}

/**
 * This function is computing an average rate and returns the result.
 *
 * @param a A BigNumber
 * @param b A BigNumber
 * @returns The weighted rate and the total balance.
 */
async function getWeightedRate(
  p2pRate: BigNumber,
  poolRate: BigNumber,
  balanceInP2P: BigNumber,
  balanceOnPool: BigNumber
): Promise<[BigNumber, BigNumber]> {
  let weightedRate = BigNumber.from(0);
  let totalBalance: BigNumber = balanceInP2P.add(balanceOnPool);
  if (totalBalance.isZero()) return [weightedRate, totalBalance];
  if (balanceInP2P.gt(0)) {
    weightedRate = weightedRate.add(
      p2pRate.mul(balanceInP2P).div(totalBalance)
    );
  }
  if (balanceOnPool.gt(0)) {
    weightedRate = weightedRate.add(
      poolRate.mul(balanceOnPool).div(totalBalance)
    );
  }
  return [weightedRate, totalBalance];
}

/**
 * This function Executes a weighted average (x * (1 - p) + y * p), rounded up and returns the result.
 *
 * @param x The first value, with a weight of 1 - percentage.
 * @param y The second value, with a weight of percentage.
 * @param percentage The weight of y, and complement of the weight of x.
 * @returns The result of the weighted average.
 */
async function getWeightedAvg(
  x: BigNumber,
  y: BigNumber,
  percentage: BigNumber
): Promise<BigNumber> {
  const PERCENTAGE_FACTOR = BigNumber.from(1e4);
  const HALF_PERCENTAGE_FACTOR = BigNumber.from(0.5e4);
  const MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR = BigNumber.from(
    2 ** 256 - 1
  ).sub(HALF_PERCENTAGE_FACTOR);
  let z: BigNumber = PERCENTAGE_FACTOR.sub(percentage);

  if (
    percentage.gt(PERCENTAGE_FACTOR) ||
    (percentage.gt(0) &&
      y.gt(MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR.div(percentage))) ||
    (PERCENTAGE_FACTOR.gt(percentage) &&
      x.gt(
        MAX_UINT256_MINUS_HALF_PERCENTAGE_FACTOR.sub(y.mul(percentage)).div(z)
      ))
  ) {
    throw new Error("Underflow or overflow detected");
  }

  z = x
    .mul(z)
    .add(y.mul(percentage))
    .add(HALF_PERCENTAGE_FACTOR)
    .div(PERCENTAGE_FACTOR);

  return z;
}

/// FUNCTIONS

/**
 * This function retrieve the total supply over the Morpho Markets and returns the result.
 *
 * @returns The P2P amount, the pool amount, the idle supply amount and the total supply amount.
 */
async function getTotalSupply(): Promise<
  [BigNumber, BigNumber, BigNumber, BigNumber]
> {
  let markets = await morpho.marketsCreated();
  let nbMarkets = markets.length;
  let p2pSupplyAmount = BigNumber.from(0);
  let poolSupplyAmount = BigNumber.from(0);
  let idleSupply = BigNumber.from(0);
  let totalSupplyAmount = BigNumber.from(0);
  for (let i = 0; i < nbMarkets; ) {
    let _poolToken = markets[i];
    const aToken = new ethers.Contract(
      _poolToken.toString(),
      ATokenAbi,
      signer
    );
    let market: Market = await morpho.market(_poolToken);
    let underlyingPrice = await oracle.getAssetPrice(market.underlying);
    let [, , , reserveDecimals, ,] = await pool
      .getConfiguration(market.underlying)
      .getParamsMemory();
    let tokenUnit = 10 ** reserveDecimals;
    p2pSupplyAmount.add(
      zeroFloorSub(
        WadRayMath.rayMul(
          market.deltas.supply.scaledP2PTotal,
          market.indexes.supply.p2pIndex
        ),
        WadRayMath.rayMul(
          market.deltas.supply.scaledDelta,
          market.indexes.supply.poolIndex
        )
      )
        .mul(underlyingPrice)
        .div(tokenUnit)
    );
    poolSupplyAmount.add(aToken.balanceOf(morpho.address));
    ++i;
    idleSupply.add(market.idleSupply);
  }
  totalSupplyAmount = p2pSupplyAmount.add(poolSupplyAmount).add(idleSupply);
  return [p2pSupplyAmount, poolSupplyAmount, idleSupply, totalSupplyAmount];
}

/**
 * This function retrieve the total borrow over the Morpho Markets and returns the result.
 *
 * @returns The P2P amount, the pool amount and the total borrow amount.
 */
async function getTotalBorrow(): Promise<[BigNumber, BigNumber, BigNumber]> {
  let markets = await morpho.marketsCreated();
  let nbMarkets = markets.length;
  let p2pBorrowAmount = BigNumber.from(0);
  let poolBorrowAmount = BigNumber.from(0);
  let totalBorrowAmount = BigNumber.from(0);
  for (let i = 0; i < nbMarkets; ) {
    let _poolToken = markets[i];
    const aToken = new ethers.Contract(
      _poolToken.toString(),
      ATokenAbi,
      signer
    );
    let market: Market = await morpho.market(_poolToken);
    let underlyingPrice = await oracle.getAssetPrice(market.underlying);
    let [, , , reserveDecimals, ,] = await pool
      .getConfiguration(market.underlying)
      .getParamsMemory();
    let tokenUnit = 10 ** reserveDecimals;
    p2pBorrowAmount.add(
      zeroFloorSub(
        WadRayMath.rayMul(
          market.deltas.borrow.scaledP2PTotal,
          market.indexes.borrow.p2pIndex
        ),
        WadRayMath.rayMul(
          market.deltas.borrow.scaledDelta,
          market.indexes.borrow.poolIndex
        )
      )
        .mul(underlyingPrice)
        .div(tokenUnit)
    );
    poolBorrowAmount.add(aToken.balanceOf(morpho.address));
    ++i;
  }
  totalBorrowAmount = p2pBorrowAmount.add(poolBorrowAmount);
  return [p2pBorrowAmount, poolBorrowAmount, totalBorrowAmount];
}

/**
 * This function get the total supply over one of the Morpho Markets and returns the result.
 *
 * @param poolToken The string of the address of the aToken
 * @returns The P2P amount, the pool amount, the idle supply amount and the total supply amount of this aToken.
 */
async function getTotalMarketSupply(
  poolToken: string
): Promise<[BigNumber, BigNumber, BigNumber, BigNumber]> {
  const aToken = new ethers.Contract(poolToken, ATokenAbi, signer);
  let market: Market = await morpho.market(poolToken);
  let underlyingPrice = await oracle.getAssetPrice(market.underlying);
  let [, , , reserveDecimals, ,] = await pool
    .getConfiguration(market.underlying)
    .getParamsMemory();
  let tokenUnit = 10 ** reserveDecimals;
  let p2pSupplyAmount: BigNumber = zeroFloorSub(
    WadRayMath.rayMul(
      market.deltas.supply.scaledP2PTotal,
      market.indexes.supply.p2pIndex
    ),
    WadRayMath.rayMul(
      market.deltas.supply.scaledDelta,
      market.indexes.supply.poolIndex
    )
  )
    .mul(underlyingPrice)
    .div(tokenUnit);
  let poolSupplyAmount: BigNumber = aToken.balanceOf(morpho.address);
  let idleSupply: BigNumber = market.idleSupply;
  let totalSupplyAmount: BigNumber = p2pSupplyAmount
    .add(poolSupplyAmount)
    .add(idleSupply);
  return [p2pSupplyAmount, poolSupplyAmount, idleSupply, totalSupplyAmount];
}

/**
 * This function get the total borrow over one of the Morpho Markets and returns the result.
 *
 * @param poolToken The string of the address of the aToken
 * @returns The P2P amount, the pool amount and the total borrow amount of this aToken.
 */
async function getTotalMarketBorrow(
  poolToken: string
): Promise<[BigNumber, BigNumber, BigNumber]> {
  const aToken = new ethers.Contract(poolToken, ATokenAbi, signer);
  let market: Market = await morpho.market(poolToken);
  let underlyingPrice = await oracle.getAssetPrice(market.underlying);
  let [, , , reserveDecimals, ,] = await pool
    .getConfiguration(market.underlying)
    .getParamsMemory();
  let tokenUnit = 10 ** reserveDecimals;
  let p2pBorrowAmount: BigNumber = zeroFloorSub(
    WadRayMath.rayMul(
      market.deltas.borrow.scaledP2PTotal,
      market.indexes.borrow.p2pIndex
    ),
    WadRayMath.rayMul(
      market.deltas.borrow.scaledDelta,
      market.indexes.borrow.poolIndex
    )
  )
    .mul(underlyingPrice)
    .div(tokenUnit);
  let poolBorrowAmount: BigNumber = aToken.balanceOf(morpho.address);
  let totalBorrowAmount: BigNumber = p2pBorrowAmount.add(poolBorrowAmount);
  return [p2pBorrowAmount, poolBorrowAmount, totalBorrowAmount]; // it returns BigNumber here. We may want to transform it :)
}

/**
 * This function retrieves the supply liquidity matchable of a user given and returns the result.
 *
 * @param underlying The market to retrieve the supplied liquidity.
 * @param user The user address.
 * @returns The P2P amount, the pool amount and the total supply amount of this token.
 */
async function getCurrentSupplyBalanceInOf(
  underlying: string,
  user: string
): Promise<[BigNumber, BigNumber, BigNumber]> {
  const indexes: { supply: { p2pIndex: BigNumber; poolIndex: BigNumber } } =
    await morpho.updatedIndexes(underlying);
  const balanceInP2P: BigNumber = await morpho.scaledP2PSupplyBalance(
    underlying,
    user
  );
  const balanceOnPool: BigNumber = await morpho.scaledPoolSupplyBalance(
    underlying,
    user
  );
  const totalBalance: BigNumber = balanceInP2P
    .mul(indexes.supply.p2pIndex)
    .add(balanceOnPool.mul(indexes.supply.poolIndex));
  return [balanceInP2P, balanceOnPool, totalBalance];
}

/**
 * This function retrieves the not-matchable collateral liquidity of a user given and returns the result.
 *
 * @param underlying The market to retrieve the supplied liquidity.
 * @param user The user address.
 * @returns The collateral amount deposited of this token.
 */
async function getCurrentCollateralBalanceInOf(
  underlying: string,
  user: string
): Promise<BigNumber> {
  const collateral: BigNumber = await morpho.collateralBalance(
    underlying,
    user
  );
  return collateral;
}

/**
 * This function retrieves the borrow liquidity of a user given and returns the result.
 *
 * @param underlying The market to retrieve the borrowed liquidity.
 * @param user The user address.
 * @returns The P2P amount, the pool amount and the total borrow amount of this token.
 */
async function getCurrentBorrowBalanceInOf(
  underlying: string,
  user: string
): Promise<[BigNumber, BigNumber, BigNumber]> {
  const indexes: { borrow: { p2pIndex: BigNumber; poolIndex: BigNumber } } =
    await morpho.updatedIndexes(underlying);
  const balanceInP2P: BigNumber = await morpho.scaledP2PBorrowBalance(
    underlying,
    user
  );
  const balanceOnPool: BigNumber = await morpho.scaledPoolBorrowBalance(
    underlying,
    user
  );
  const totalBalance: BigNumber = balanceInP2P
    .mul(indexes.borrow.p2pIndex)
    .add(balanceOnPool.mul(indexes.borrow.poolIndex));
  return [balanceInP2P, balanceOnPool, totalBalance];
}

/**
 * This function retrieves the supply APY of a user on a given market and returns the result.
 *
 * @param underlying The market to retrieve the supply APY.
 * @param user The user address.
 * @returns The experienced rate and the total balance of the deposited liquidity on this market.
 */
async function getCurrentUserSupplyRatePerYear(
  underlying: string,
  user: string
) {
  let [balanceInP2P, balanceOnPool] = await getCurrentSupplyBalanceInOf(
    underlying,
    user
  );
  let balanceIdle = await getCurrentCollateralBalanceInOf(underlying, user);
  let poolAmount: BigNumber = balanceIdle.add(balanceOnPool);
  let [p2pSupplyRate, poolSupplyRate] = await getSupplyRatesPerYear(underlying);
  return await getWeightedRate(
    p2pSupplyRate,
    poolSupplyRate,
    balanceInP2P,
    poolAmount
  );
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
  let [balanceInP2P, balanceOnPool] = await getCurrentBorrowBalanceInOf(
    underlying,
    user
  );
  let [p2pSupplyRate, poolSupplyRate] = await getBorrowRatesPerYear(underlying);
  return await getWeightedRate(
    p2pSupplyRate,
    poolSupplyRate,
    balanceInP2P,
    balanceOnPool
  );
}

/**
 * This function compute the P2P supply rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 * @returns The p2p supply rate.
 */
async function getP2PSupplyRate(
  params: P2PRateComputeParams
): Promise<BigNumber> {
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
      p2pRate
        .sub(params.poolSupplyRatePerYear)
        .mul(params.reserveFactor)
        .div(WadRayMath.RAY)
    );
  }
  if (params.p2pDelta.gt(0) && params.p2pAmount.gt(0)) {
    const a = params.p2pDelta
      .mul(params.poolIndex)
      .div(params.p2pAmount.mul(params.p2pIndex));
    const b = WadRayMath.RAY;
    const shareOfTheDelta = a.gt(b) ? b : a;
    p2pSupplyRate = p2pSupplyRate
      .mul(WadRayMath.RAY.sub(shareOfTheDelta).sub(params.proportionIdle))
      .div(WadRayMath.RAY)
      .add(
        params.poolSupplyRatePerYear.mul(shareOfTheDelta).div(WadRayMath.RAY)
      );
  }
  return p2pSupplyRate;
}

/**
 * This function compute the P2P borrow rate and returns the result.
 *
 * @param params The parameters inheriting of the P2PRateComputeParams interface allowing the computation.
 * @returns The p2p borrow rate.
 */
async function getP2PBorrowRate(
  params: P2PRateComputeParams
): Promise<BigNumber> {
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
      p2pRate
        .sub(params.poolBorrowRatePerYear)
        .mul(params.reserveFactor)
        .div(WadRayMath.RAY)
    );
  }
  if (params.p2pDelta.gt(0) && params.p2pAmount.gt(0)) {
    const a = params.p2pDelta
      .mul(params.poolIndex)
      .div(params.p2pAmount.mul(params.p2pIndex));
    const b = WadRayMath.RAY;
    const shareOfTheDelta = a.gt(b) ? b : a;
    p2pBorrowRate = p2pBorrowRate
      .mul(WadRayMath.RAY.sub(shareOfTheDelta))
      .div(WadRayMath.RAY)
      .add(
        params.poolBorrowRatePerYear.mul(shareOfTheDelta).div(WadRayMath.RAY)
      );
  }
  return p2pBorrowRate;
}

/**
 * This function compute the supply rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the supply APY.
 * @returns The P2P supply rate and the pool supply rate.
 */
async function getSupplyRatesPerYear(
  underlying
): Promise<[BigNumber, BigNumber]> {
  let reserve = await pool.getReserveData(underlying);
  let market = await morpho.market(underlying);

  let idleSupply: BigNumber = market.idleSupply;
  let totalP2PSupplied: BigNumber = WadRayMath.rayMul(
    market.deltas.supply.scaledP2PTotal,
    market.indexes.supply.p2pIndex
  );
  let propIdleSupply = WadRayMath.rayDiv(idleSupply, totalP2PSupplied);

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

  let P2PSupplyRate = await getP2PSupplyRate(params);
  return [P2PSupplyRate, params.poolSupplyRatePerYear];
}

/**
 * This function compute the borrow rate on a specific asset and returns the result.
 *
 * @param underlying The market to retrieve the borrow APY.
 * @returns The P2P borrow rate and the pool borrow rate.
 */
async function getBorrowRatesPerYear(
  underlying
): Promise<[BigNumber, BigNumber]> {
  let reserve = await pool.getReserveData(underlying);
  let market = await morpho.market(underlying);
  let totalP2PBorrowed: BigNumber = WadRayMath.rayMul(
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

  let P2PBorrowRate = await getP2PBorrowRate(params);
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
  let healthFactor = WadRayMath.rayDiv(
    liquidityData.maxDebt,
    liquidityData.debt
  );
  return healthFactor;
}
