// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IAToken} from "@aave-v3-core/interfaces/IAToken.sol";
import {IReserveInterestRateStrategy} from "@aave-v3-core/interfaces/IReserveInterestRateStrategy.sol";
import {IStableDebtToken} from "@aave-v3-core/interfaces/IStableDebtToken.sol";
import {IMorpho} from "@morpho-aave-v3/interfaces/IMorpho.sol";

import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Types} from "@morpho-aave-v3/libraries/Types.sol";

/// @title Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Snippet for Morpho-Aave V3.
contract Snippets {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    struct P2PRateComputeParams {
        uint256 poolSupplyRatePerYear;
        uint256 poolBorrowRatePerYear;
        uint256 poolIndex;
        uint256 p2pIndex;
        uint256 proportionIdle;
        uint256 p2pDelta;
        uint256 p2pAmount;
        uint256 p2pIndexCursor;
        uint256 reserveFactor;
    }

    IMorpho public immutable morpho;
    IPoolAddressesProvider public addressesProvider;
    IPool public pool;
    uint8 public eModeCategoryId;

    constructor(address morphoAddress) {
        morpho = IMorpho(morphoAddress);
        pool = IPool(morpho.pool());
        addressesProvider = IPoolAddressesProvider(morpho.addressesProvider());
        eModeCategoryId = uint8(morpho.eModeCategoryId());
    }

    /// @notice Computes and returns the total distribution of supply through Morpho, using virtually updated indexes.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta and the idle supply on Morpho's contract (in base currency).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in base currency).
    /// @return idleSupplyAmount The total idle supply amount on the Morpho's contract (in base currency).
    /// @return totalSupplyAmount The total amount supplied through Morpho (in base currency).
    function totalSupply()
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount)
    {
        address[] memory marketAddresses = morpho.marketsCreated();

        uint256 underlyingPrice;
        uint256 nbMarkets = marketAddresses.length;

        for (uint256 i; i < nbMarkets; ++i) {
            address underlying = marketAddresses[i];

            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);
            underlyingPrice = assetPrice(config, underlying);
            uint256 assetUnit = 10 ** config.getDecimals();

            (uint256 marketP2PSupplyAmount, uint256 marketPoolSupplyAmount, uint256 marketIdleSupplyAmount) =
                marketSupply(underlying);

            p2pSupplyAmount += (marketP2PSupplyAmount * underlyingPrice) / assetUnit;
            poolSupplyAmount += (marketPoolSupplyAmount * underlyingPrice) / assetUnit;
            idleSupplyAmount += (marketIdleSupplyAmount * underlyingPrice) / assetUnit;
        }

        totalSupplyAmount = p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount;
    }

    /// @notice Computes and returns the total distribution of borrows through Morpho, using virtually updated indexes.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in base currency).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in base currency).
    /// @return totalBorrowAmount The total amount borrowed through Morpho (in base currency).
    function totalBorrow()
        public
        view
        returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount)
    {
        address[] memory marketAddresses = morpho.marketsCreated();

        uint256 underlyingPrice;
        uint256 nbMarkets = marketAddresses.length;

        for (uint256 i; i < nbMarkets; ++i) {
            address underlying = marketAddresses[i];

            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);
            underlyingPrice = assetPrice(config, underlying);
            uint256 assetUnit = 10 ** config.getDecimals();

            (uint256 marketP2PBorrowAmount, uint256 marketPoolBorrowAmount) = marketBorrow(underlying);

            p2pBorrowAmount += (marketP2PBorrowAmount * underlyingPrice) / assetUnit;
            poolBorrowAmount += (marketPoolBorrowAmount * underlyingPrice) / assetUnit;
        }

        totalBorrowAmount = p2pBorrowAmount + poolBorrowAmount;
    }

    /// @notice Returns the supply rate per year a given user is currently experiencing on a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to compute the supply rate per year for.
    /// @return supplyRatePerYear The supply rate per year the user is currently experiencing (in ray).
    function supplyAPR(address underlying, address user) public view returns (uint256 supplyRatePerYear) {
        (uint256 balanceInP2P, uint256 balanceOnPool,) = supplyBalance(underlying, user);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = poolAPR(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pSupplyRate = p2pSupplyAPR(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: proportionIdle(market),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pAmount: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        supplyRatePerYear = weightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, balanceOnPool);
    }

    /// @notice Returns the borrow rate per year a given user is currently experiencing on a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to compute the borrow rate per year for.
    /// @return borrowRatePerYear The borrow rate per year the user is currently experiencing (in ray).
    function borrowAPR(address underlying, address user) public view returns (uint256 borrowRatePerYear) {
        (uint256 balanceInP2P, uint256 balanceOnPool,) = borrowBalance(underlying, user);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = poolAPR(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pBorrowRate = p2pBorrowAPR(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pAmount: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        borrowRatePerYear = weightedRate(p2pBorrowRate, poolBorrowRate, balanceInP2P, balanceOnPool);
    }

    /// @notice Computes and returns the current borrow rate per year experienced on average on a given market.
    /// @param underlying The address of the underlying asset.
    /// @return avgBorrowRatePerYear The market's average borrow rate per year (in ray).
    /// @return p2pBorrowRatePerYear The market's p2p borrow rate per year (in ray).
    ///@return poolBorrowRatePerYear The market's pool borrow rate per year (in ray).
    function avgBorrowAPR(address underlying)
        public
        view
        returns (uint256 avgBorrowRatePerYear, uint256 p2pBorrowRatePerYear, uint256 poolBorrowRatePerYear)
    {
        uint256 poolSupplyRatePerYear;
        Types.Market memory market = morpho.market(underlying);

        (poolSupplyRatePerYear, poolBorrowRatePerYear) = poolAPR(underlying);

        p2pBorrowRatePerYear = p2pBorrowAPR(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRatePerYear,
                poolBorrowRatePerYear: poolBorrowRatePerYear,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pAmount: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        avgBorrowRatePerYear = weightedRate(
            p2pBorrowRatePerYear,
            poolBorrowRatePerYear,
            market.deltas.borrow.scaledP2PTotal.rayMul(market.indexes.borrow.p2pIndex),
            ERC20(market.variableDebtToken).balanceOf(address(morpho)).zeroFloorSub(
                market.deltas.borrow.scaledDelta.rayMul(market.indexes.borrow.poolIndex)
            )
        );
    }

    /// @notice Returns the health factor of a given user.
    /// @param user The user of whom to get the health factor.
    /// @return healthFactor The health factor of the given user (in wad).
    function userHealthFactor(address user) public view returns (uint256 healthFactor) {
        Types.LiquidityData memory liquidityData = morpho.liquidityData(user);

        healthFactor = liquidityData.debt > 0 ? liquidityData.maxDebt.wadDiv(liquidityData.debt) : type(uint256).max;
    }

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @notice It takes into account the amount of token deposit in supply and in collateral in Morpho.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pSupplyAmount The total supplied amount matched peer-to-peer, subtracting the supply delta (in underlying) and the idle supply (in underlying).
    /// @return poolSupplyAmount The total supplied amount on the underlying pool, adding the supply delta (in underlying).
    /// @return idleSupplyAmount The total idle amount on the morpho's contract (in underlying).
    function marketSupply(address underlying)
        public
        view
        returns (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount)
    {
        Types.Market memory market = morpho.market(underlying);

        poolSupplyAmount = IAToken(market.aToken).balanceOf(address(morpho));
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pSupplyAmount = market.deltas.supply.scaledP2PTotal.rayMul(indexes.supply.p2pIndex).zeroFloorSub(
            market.deltas.supply.scaledDelta.rayMul(indexes.supply.poolIndex)
        ).zeroFloorSub(market.idleSupply);
        idleSupplyAmount = market.idleSupply;
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pBorrowAmount The total borrowed amount matched peer-to-peer, subtracting the borrow delta (in underlying).
    /// @return poolBorrowAmount The total borrowed amount on the underlying pool, adding the borrow delta (in underlying).
    function marketBorrow(address underlying) public view returns (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) {
        Types.Market memory market = morpho.market(underlying);

        poolBorrowAmount = ERC20(market.variableDebtToken).balanceOf(address(morpho));
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pBorrowAmount = market.deltas.borrow.scaledP2PTotal.rayMul(indexes.borrow.p2pIndex).zeroFloorSub(
            market.deltas.borrow.scaledDelta.rayMul(indexes.borrow.poolIndex)
        );
    }

    /// @notice Returns the balance in underlying of a given user in a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function supplyBalance(address underlying, address user)
        public
        view
        returns (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance)
    {
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);
        balanceInP2P = morpho.scaledP2PSupplyBalance(underlying, user).rayMulDown(indexes.supply.p2pIndex);
        balanceOnPool = morpho.scaledPoolSupplyBalance(underlying, user).rayMulDown(indexes.supply.poolIndex);
        totalBalance = balanceInP2P + balanceOnPool;
    }

    /// @notice Returns the borrow balance in underlying of a given user in a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to determine balances of.
    /// @return balanceInP2P The balance in peer-to-peer of the user (in underlying).
    /// @return balanceOnPool The balance on pool of the user (in underlying).
    /// @return totalBalance The total balance of the user (in underlying).
    function borrowBalance(address underlying, address user)
        public
        view
        returns (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance)
    {
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);
        balanceInP2P = morpho.scaledP2PBorrowBalance(underlying, user).rayMulUp(indexes.borrow.p2pIndex);
        balanceOnPool = morpho.scaledPoolBorrowBalance(underlying, user).rayMulUp(indexes.borrow.poolIndex);
        totalBalance = balanceInP2P + balanceOnPool;
    }

    /// @dev Computes and returns the underlying pool rates for a specific market.
    /// @param underlying The underlying pool market address.
    /// @return poolSupplyRatePerYear The market's pool supply rate per year (in ray).
    /// @return poolBorrowRatePerYear The market's pool borrow rate per year (in ray).
    function poolAPR(address underlying)
        public
        view
        returns (uint256 poolSupplyRatePerYear, uint256 poolBorrowRatePerYear)
    {
        DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
        poolSupplyRatePerYear = reserve.currentLiquidityRate;
        poolBorrowRatePerYear = reserve.currentVariableBorrowRate;
    }

    /// @notice Computes and return the price of an asset for Morpho User.
    /// @param config The configuration of the Morpho's user on Aave.
    /// @param asset The address of the underlying asset to get the Price.
    /// @return price The current underlying price of the asset given Morpho's configuration
    function assetPrice(DataTypes.ReserveConfigurationMap memory config, address asset)
        public
        view
        returns (uint256 price)
    {
        IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());
        DataTypes.EModeCategory memory categoryEModeData = pool.getEModeCategoryData(eModeCategoryId);

        bool isInEMode = eModeCategoryId != 0 && config.getEModeCategory() == eModeCategoryId;

        if (isInEMode && categoryEModeData.priceSource != address(0)) {
            price = oracle.getAssetPrice(categoryEModeData.priceSource);
            if (price != 0) oracle.getAssetPrice(asset);
        } else {
            price = oracle.getAssetPrice(asset);
        }
    }

    /// @dev Returns the rate experienced based on a given pool & peer-to-peer distribution.
    /// @param p2pRate The peer-to-peer rate (in a unit common to `poolRate` & `globalRate`).
    /// @param poolRate The pool rate (in a unit common to `p2pRate` & `globalRate`).
    /// @param balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `balanceOnPool`).
    /// @param balanceOnPool The amount of balance supplied on pool (in a unit common to `balanceInP2P`).
    /// @return globalRate The rate experienced by the given distribution (in a unit common to `p2pRate` & `poolRate`).
    function weightedRate(uint256 p2pRate, uint256 poolRate, uint256 balanceInP2P, uint256 balanceOnPool)
        public
        pure
        returns (uint256 globalRate)
    {
        uint256 totalBalance = balanceInP2P + balanceOnPool;
        if (totalBalance == 0) return (globalRate);

        if (balanceInP2P > 0) globalRate += p2pRate.rayMul(balanceInP2P.rayDiv(totalBalance));
        if (balanceOnPool > 0) {
            globalRate += poolRate.rayMul(balanceOnPool.rayDiv(totalBalance));
        }
    }

    /// @notice Computes and returns the peer-to-peer borrow rate per year of a market given its parameters.
    /// @param params The computation parameters.
    /// @return p2pBorrowRate The peer-to-peer borrow rate per year (in ray).
    function p2pBorrowAPR(P2PRateComputeParams memory params) public pure returns (uint256 p2pBorrowRate) {
        if (params.poolSupplyRatePerYear > params.poolBorrowRatePerYear) {
            p2pBorrowRate = params.poolBorrowRatePerYear; // The p2pBorrowRate is set to the poolBorrowRatePerYear because there is no rate spread.
        } else {
            uint256 p2pRate = PercentageMath.weightedAvg(
                params.poolSupplyRatePerYear, params.poolBorrowRatePerYear, params.p2pIndexCursor
            );
            p2pBorrowRate = p2pRate + (params.poolBorrowRatePerYear - p2pRate).percentMul(params.reserveFactor);
        }

        if (params.p2pDelta > 0 && params.p2pAmount > 0) {
            uint256 proportionDelta = Math.min(
                params.p2pDelta.rayMul(params.poolIndex).rayDivUp(params.p2pAmount.rayMul(params.p2pIndex)), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid proportionDelta > 1 with rounding errors.
            ); // In ray.

            p2pBorrowRate = p2pBorrowRate.rayMul(WadRayMath.RAY - proportionDelta)
                + params.poolBorrowRatePerYear.rayMul(proportionDelta);
        }
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
    function p2pSupplyAPR(P2PRateComputeParams memory params) public pure returns (uint256 p2pSupplyRate) {
        if (params.poolSupplyRatePerYear > params.poolBorrowRatePerYear) {
            p2pSupplyRate = params.poolBorrowRatePerYear; // The p2pSupplyRate is set to the poolBorrowRatePerYear because there is no rate spread.
        } else {
            uint256 p2pRate = PercentageMath.weightedAvg(
                params.poolSupplyRatePerYear, params.poolBorrowRatePerYear, params.p2pIndexCursor
            );

            p2pSupplyRate = p2pRate - (p2pRate - params.poolSupplyRatePerYear).percentMul(params.reserveFactor);
        }

        if ((params.p2pDelta > 0 || params.proportionIdle > 0) && params.p2pAmount > 0) {
            uint256 proportionDelta = Math.min(
                params.p2pDelta.rayMul(params.poolIndex).rayDivUp(params.p2pAmount.rayMul(params.p2pIndex)), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY - params.proportionIdle // To avoid proportionDelta > 1 - proportionIdle with rounding errors.
            ); // In ray.

            p2pSupplyRate = p2pSupplyRate.rayMul(WadRayMath.RAY - proportionDelta - params.proportionIdle)
                + params.poolSupplyRatePerYear.rayMul(proportionDelta);
        }
    }

    /// @notice Returns the proportion of idle supply in `market` over the total peer-to-peer amount in supply.
    function proportionIdle(Types.Market memory market) public pure returns (uint256) {
        uint256 idleSupply = market.idleSupply;
        if (idleSupply == 0) return 0;

        uint256 totalP2PSupplied = market.deltas.supply.scaledP2PTotal.rayMul(market.indexes.supply.p2pIndex);
        return Math.min(idleSupply.rayDivUp(totalP2PSupplied), WadRayMath.RAY);
    }
}
