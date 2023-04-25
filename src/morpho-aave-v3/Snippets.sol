// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-v3-core/interfaces/IAaveOracle.sol";
import {IMorpho} from "@morpho-aave-v3/interfaces/IMorpho.sol";

import {Utils} from "@snippets/Utils.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Types} from "@morpho-aave-v3/libraries/Types.sol";
import {MarketLib} from "@snippets/libraries/MarketLib.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

/// @title Snippets
/// @author Morpho Labs
/// @custom:contact security@morpho.xyz
/// @notice Code snippets for Morpho-Aave V3.
contract Snippets {
    using Math for uint256;
    using WadRayMath for uint256;
    using MarketLib for Types.Market;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IMorpho public immutable morpho;
    IPoolAddressesProvider public immutable addressesProvider;
    IPool public immutable pool;
    uint8 public immutable eModeCategoryId;

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

            DataTypes.ReserveConfigurationMap memory reserve = pool.getConfiguration(underlying);
            underlyingPrice = assetPrice(underlying, reserve.getEModeCategory());
            uint256 assetUnit = 10 ** reserve.getDecimals();

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

            DataTypes.ReserveConfigurationMap memory reserve = pool.getConfiguration(underlying);
            underlyingPrice = assetPrice(underlying, reserve.getEModeCategory());
            uint256 assetUnit = 10 ** reserve.getDecimals();

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
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: indexes.supply.poolIndex,
                p2pIndex: indexes.supply.p2pIndex,
                proportionIdle: market.proportionIdle(),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pTotal: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        supplyRatePerYear = Utils.weightedRate(p2pSupplyRate, poolSupplyRate, balanceInP2P, balanceOnPool);
    }

    /// @notice Returns the borrow rate per year a given user is currently experiencing on a given market.
    /// @param underlying The address of the underlying asset.
    /// @param user The user to compute the borrow rate per year for.
    /// @return borrowRatePerYear The borrow rate per year the user is currently experiencing (in ray).
    function borrowAPR(address underlying, address user) public view returns (uint256 borrowRatePerYear) {
        (uint256 balanceInP2P, uint256 balanceOnPool,) = borrowBalance(underlying, user);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = poolAPR(underlying);

        Types.Market memory market = morpho.market(underlying);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: indexes.borrow.poolIndex,
                p2pIndex: indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pTotal: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        borrowRatePerYear = Utils.weightedRate(p2pBorrowRate, poolBorrowRate, balanceInP2P, balanceOnPool);
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
        Types.Market memory market = morpho.market(underlying);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        uint256 poolSupplyRatePerYear;
        (poolSupplyRatePerYear, poolBorrowRatePerYear) = poolAPR(underlying);

        p2pBorrowRatePerYear = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRatePerYear,
                poolBorrowRatePerYear: poolBorrowRatePerYear,
                poolIndex: indexes.borrow.poolIndex,
                p2pIndex: indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0, // Simpler to account for the delta in the weighted avg.
                p2pTotal: 0,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        avgBorrowRatePerYear = Utils.weightedRate(
            p2pBorrowRatePerYear,
            poolBorrowRatePerYear,
            market.trueP2PBorrow(indexes),
            ERC20(market.variableDebtToken).balanceOf(address(morpho))
        );
    }

    /// @notice Returns the health factor of a given user.
    /// @param user The user of whom to get the health factor.
    /// @return The health factor of the given user (in wad).
    function healthFactor(address user) public view returns (uint256) {
        Types.LiquidityData memory liquidityData = morpho.liquidityData(user);

        return liquidityData.debt > 0 ? liquidityData.maxDebt.wadDiv(liquidityData.debt) : type(uint256).max;
    }

    /// @notice Computes and returns the total distribution of supply for a given market, using virtually updated indexes.
    /// @notice It takes into account the amount of token deposit in supply and in collateral in Morpho.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pSupply The total supplied amount (in underlying) matched peer-to-peer, subtracting the supply delta and the idle supply.
    /// @return poolSupply The total supplied amount (in underlying) on the underlying pool, adding the supply delta.
    /// @return idleSupply The total idle amount (in underlying) on the Morpho contract.
    function marketSupply(address underlying)
        public
        view
        returns (uint256 p2pSupply, uint256 poolSupply, uint256 idleSupply)
    {
        Types.Market memory market = morpho.market(underlying);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pSupply = market.trueP2PSupply(indexes);
        poolSupply = ERC20(market.aToken).balanceOf(address(morpho));
        idleSupply = market.idleSupply;
    }

    /// @notice Computes and returns the total distribution of borrows for a given market, using virtually updated indexes.
    /// @param underlying The address of the underlying asset to check.
    /// @return p2pBorrow The total borrowed amount (in underlying) matched peer-to-peer, subtracting the borrow delta.
    /// @return poolBorrow The total borrowed amount (in underlying) on the underlying pool, adding the borrow delta.
    function marketBorrow(address underlying) public view returns (uint256 p2pBorrow, uint256 poolBorrow) {
        Types.Market memory market = morpho.market(underlying);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(underlying);

        p2pBorrow = market.trueP2PBorrow(indexes);
        poolBorrow = ERC20(market.variableDebtToken).balanceOf(address(morpho));
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

    /// @notice Returns the price of a given asset.
    /// @param asset The address of the asset to get the price of.
    /// @param reserveEModeCategoryId Aave's associated reserve e-mode category.
    /// @return price The current price of the asset.
    function assetPrice(address asset, uint256 reserveEModeCategoryId) public view returns (uint256 price) {
        address priceSource;
        if (eModeCategoryId != 0 && reserveEModeCategoryId == eModeCategoryId) {
            priceSource = pool.getEModeCategoryData(eModeCategoryId).priceSource;
        }

        IAaveOracle oracle = IAaveOracle(addressesProvider.getPriceOracle());

        if (priceSource != address(0)) {
            price = oracle.getAssetPrice(priceSource);
        }

        if (priceSource == address(0) || price == 0) {
            price = oracle.getAssetPrice(asset);
        }
    }
}
