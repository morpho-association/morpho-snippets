// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Constants} from "@morpho-aave-v3/libraries/Constants.sol";

import {MarketLib} from "@snippets/morpho-aave-v3/libraries/MarketLib.sol";
import {Snippets} from "@snippets/morpho-aave-v3/Snippets.sol";
import {Utils} from "@snippets/morpho-aave-v3/Utils.sol";

import "lib/morpho-aave-v3/test/helpers/IntegrationTest.sol";

contract TestIntegrationSnippets is IntegrationTest {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using MarketLib for Types.Market;
    using TestMarketLib for TestMarket;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    Snippets internal snippets;

    struct ExpectedSupply {
        uint256 totalSupply;
        uint256 poolSupply;
        uint256 p2pSupply;
        uint256 idleSupply;
    }

    function setUp() public virtual override {
        super.setUp();
        snippets = new Snippets(address(morpho));
    }

    function testTotalSupplyShouldBeZeroIfNoAction() public {
        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount) =
            snippets.totalSupply();

        assertApproxEqAbs(totalSupplyAmount, 0, 1e9, "Incorrect total supply amount");
        // The tolerance is due to the initial deposit made at the creation of the market.
        assertApproxEqAbs(poolSupplyAmount, 0, 1e9, "Incorrect total borrow amount");
        assertApproxEqAbs(p2pSupplyAmount, 0, 1, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, 0, 1, "Incorrect Idle supply amount");
        assertEq(p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount, totalSupplyAmount, "Incorrect values returned");
    }

    function testTotalBorrowShouldBeZeroIfNoAction() public {
        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount) = snippets.totalBorrow();

        assertApproxEqAbs(totalBorrowAmount, 0, 1, "Incorrect total borrow amount");
        assertApproxEqAbs(poolBorrowAmount, 0, 1, "Incorrect total borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, 0, 1, "Incorrect P2P borrow amount");
        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }

    function testTotalSupply(uint256[] memory amounts, uint256[] memory idleAmounts, uint256 promotionFactor) public {
        ExpectedSupply memory expected;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);

        vm.assume(amounts.length >= allUnderlyings.length);
        vm.assume(idleAmounts.length >= allUnderlyings.length);

        DataTypes.ReserveConfigurationMap memory daiReserve = pool.getConfiguration(dai);
        uint256 daiPrice = snippets.assetPrice(dai, daiReserve.getEModeCategory());

        for (uint256 i; i < borrowableInEModeUnderlyings.length; ++i) {
            address underlying = borrowableInEModeUnderlyings[i];

            DataTypes.ReserveConfigurationMap memory reserve = pool.getConfiguration(underlying);
            uint256 assetUnit = 10 ** reserve.getDecimals();
            uint256 price = snippets.assetPrice(underlying, reserve.getEModeCategory());

            uint256 amount = _boundSupply(testMarkets[underlying], amounts[i]);
            uint256 promoted = _promoteSupply(promoter1, testMarkets[underlying], amount.wadMul(promotionFactor));

            user.approve(underlying, amount);
            user.supply(underlying, amount);

            idleAmounts[i] = _boundBorrow(testMarkets[underlying], idleAmounts[i]);
            idleAmounts[i] = _increaseIdleSupply(promoter2, testMarkets[underlying], idleAmounts[i]);

            expected.p2pSupply += (promoted * price) / assetUnit;
            expected.totalSupply += ((amount + idleAmounts[i]) * price) / assetUnit;
            expected.totalSupply += (
                testMarkets[dai].minBorrowCollateral(testMarkets[underlying], promoted, eModeCategoryId) * daiPrice
            ) / (10 ** daiReserve.getDecimals());

            expected.totalSupply += (
                testMarkets[dai].minBorrowCollateral(testMarkets[underlying], idleAmounts[i], eModeCategoryId)
                    * daiPrice
            ) / (10 ** daiReserve.getDecimals());
            expected.idleSupply += (idleAmounts[i] * price) / assetUnit;
        }

        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount) =
            snippets.totalSupply();

        assertApproxEqAbs(totalSupplyAmount, expected.totalSupply, 1e9, "Incorrect total supply amount");
        assertApproxEqAbs(p2pSupplyAmount, expected.p2pSupply, 1e9, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, expected.idleSupply, 1e9, "Incorrect idle supply amount");
        assertEq(p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount, totalSupplyAmount, "Incorrect values returned");
    }

    function testTotalBorrow(uint256[15] memory amounts, uint256[15] memory idleAmounts, uint256 promotionFactor)
        public
    {
        uint256 expectedTotalBorrow;
        uint256 expectedP2PBorrow;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);

        vm.assume(amounts.length >= borrowableInEModeUnderlyings.length);
        vm.assume(idleAmounts.length >= borrowableInEModeUnderlyings.length);

        for (uint256 i; i < borrowableInEModeUnderlyings.length; ++i) {
            address underlying = borrowableInEModeUnderlyings[i];

            DataTypes.ReserveConfigurationMap memory reserve = pool.getConfiguration(underlying);
            uint256 assetUnit = 10 ** reserve.getDecimals();
            uint256 price = snippets.assetPrice(underlying, reserve.getEModeCategory());

            uint256 borrowed = _boundBorrow(testMarkets[underlying], amounts[i]);

            (, uint256 realborrowed) = _borrowWithCollateral(
                address(user),
                testMarkets[dai],
                testMarkets[underlying],
                borrowed,
                address(user),
                address(user),
                DEFAULT_MAX_ITERATIONS
            );
            _promoteBorrow(promoter1, testMarkets[underlying], realborrowed.wadMul(promotionFactor));

            expectedP2PBorrow += (realborrowed.wadMul(promotionFactor) * price) / assetUnit;
            expectedTotalBorrow += (realborrowed * price) / assetUnit;
        }

        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount) = snippets.totalBorrow();

        assertApproxEqAbs(totalBorrowAmount, expectedTotalBorrow, 1e9, "Incorrect total borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, expectedP2PBorrow, 1e9, "Incorrect P2P borrow amount");
        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }

    function testSupplyAPRShouldEqual0WhenNoSupply(address user, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, user);

        assertEq(supplyRatePerYear, 0, "Incorrect supply APR");
    }

    function testBorrowAPRShouldEqual0WhenNoBorrow(address user, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, user);

        assertEq(borrowRatePerYear, 0, "Incorrect borrow APR");
    }

    function testSupplyAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        amount = _boundSupply(testMarket, amount);
        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);

        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, address(user));
        DataTypes.ReserveData memory reserve = pool.getReserveData(testMarket.underlying);
        uint256 poolSupplyRatePerYear = reserve.currentLiquidityRate;

        assertEq(supplyRatePerYear, poolSupplyRatePerYear, "Incorrect supply APR");
    }

    function testBorrowAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        address onBehalf = address(user);
        amount = _boundBorrow(testMarket, amount);

        _borrowWithoutCollateral(onBehalf, testMarket, amount, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);

        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, onBehalf);
        DataTypes.ReserveData memory reserve = pool.getReserveData(testMarket.underlying);
        uint256 poolBorrowRatePerYear = reserve.currentVariableBorrowRate;
        assertEq(borrowRatePerYear, poolBorrowRatePerYear, "Incorrect borrow APR");
    }

    function testSupplyAPRUserRateShouldMatchP2PRateWhenFullyMatched(uint256 amount, uint256 supplyCap, uint256 seed)
        public
    {
        address onBehalf = address(user);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        amount = _boundSupply(testMarket, amount);
        amount = _promoteSupply(promoter1, testMarket, amount) - 1; // 100% peer-to-peer. Minus 1 so that the test passes for now.

        supplyCap = _boundSupplyCapExceeded(testMarket, 0, supplyCap);
        _setSupplyCap(testMarket, supplyCap);

        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);

        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, onBehalf);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(testMarket.underlying);

        Types.Market memory market = morpho.market(testMarket.underlying);

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: market.proportionIdle(),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pTotal: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        assertEq(supplyRatePerYear, p2pSupplyRate, "Incorrect supply APR");
    }

    function testBorrowAPRUserRateShouldMatchP2PRateWhenFullyMatched(uint256 amount, uint256 seed) public {
        address onBehalf = address(user);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];

        amount = _boundBorrow(testMarket, amount);
        amount = _promoteBorrow(promoter1, testMarket, amount); // 100% peer-to-peer.

        _borrowWithoutCollateral(onBehalf, testMarket, amount, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);

        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, onBehalf);
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(testMarket.underlying);
        Types.Market memory market = morpho.market(testMarket.underlying);

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pTotal: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        assertEq(borrowRatePerYear, p2pBorrowRate, "Incorrect borrow APR");
    }

    function testSupplyAPRWhenUserPartiallyMatched(uint256 amount, uint256 seed, uint256 promotionFactor) public {
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        amount = _boundSupply(testMarket, amount);
        vm.assume(amount.wadMul(promotionFactor) != 0);
        _promoteSupply(promoter1, testMarket, amount.wadMul(promotionFactor));

        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);

        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, address(user));

        (uint256 balanceInP2P,, uint256 totalBalance) = snippets.supplyBalance(testMarket.underlying, address(user));
        uint256 expectedSupplyRate = _computeSupplyRate(totalBalance, balanceInP2P, testMarket.underlying);

        assertEq(supplyRatePerYear, expectedSupplyRate, "Incorrect supply APR");
    }

    function testBorrowAPRWhenUserPartiallyMatched(uint256 amount, uint256 seed, uint256 promotionFactor) public {
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        amount = _boundBorrow(testMarket, amount);

        _promoteBorrow(promoter1, testMarket, amount.wadMul(promotionFactor));

        _borrowWithoutCollateral(
            address(user), testMarket, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, address(user));

        (uint256 balanceInP2P,, uint256 totalBalance) = snippets.borrowBalance(testMarket.underlying, address(user));
        uint256 expectedBorrowRate = _computeBorrowRate(totalBalance, balanceInP2P, testMarket.underlying);

        assertEq(borrowRatePerYear, expectedBorrowRate, "Incorrect borrow APR");
    }

    function testMarketSupplyShouldBeAlmostZeroIfNoAction(uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount) =
            snippets.marketSupply(testMarket.underlying);

        assertEq(p2pSupplyAmount, 0, "Incorrect p2p amount");
        assertApproxEqAbs(poolSupplyAmount, 10 ** (testMarket.decimals / 2), 20, "Incorrect pool amount");
        assertEq(idleSupplyAmount, 0, "Incorrect idle amount");
    }

    function testMarketBorrowShouldBeAlmostZeroIfNoAction(uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = snippets.marketBorrow(testMarket.underlying);

        assertEq(p2pBorrowAmount, 0, "Incorrect p2p amount");
        assertApproxEqAbs(poolBorrowAmount, 0, 1, "Incorrect pool amount");
    }

    function testMarketSupply(uint256 seed, uint256 amount, uint256 idleAmount, uint256 promotionFactor) public {
        ExpectedSupply memory expected;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        amount = _boundSupply(testMarket, amount);

        uint256 promoted = _promoteSupply(promoter1, testMarket, amount.wadMul(promotionFactor));

        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);

        if (testMarket.isBorrowable && testMarket.isInEMode) {
            idleAmount = _boundBorrow(testMarket, idleAmount);
            idleAmount = _increaseIdleSupply(promoter2, testMarket, idleAmount);
            if (testMarket.underlying == dai) {
                expected.poolSupply += testMarkets[dai].minBorrowCollateral(testMarket, idleAmount, eModeCategoryId);
            }

            expected.idleSupply += idleAmount;
        }

        expected.p2pSupply = promoted;
        expected.poolSupply += amount.zeroFloorSub(promoted);
        if (testMarket.underlying == dai) {
            expected.poolSupply += testMarkets[dai].minBorrowCollateral(testMarket, promoted, eModeCategoryId);
        }

        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount) =
            snippets.marketSupply(testMarket.underlying);

        assertApproxEqAbs(
            poolSupplyAmount, expected.poolSupply + 10 ** (testMarket.decimals / 2), 20, "Incorrect pool supply amount"
        );
        // add a second member to take into account the initial deposit.
        assertApproxEqAbs(p2pSupplyAmount, expected.p2pSupply, 2, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, expected.idleSupply, 2, "Incorrect idle supply amount");
    }

    function testMarketBorrow(uint256 seed, uint256 amount, uint256 promotionFactor) public {
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];

        uint256 borrowed = _boundBorrow(testMarket, amount);

        (, uint256 realBorrowed) = _borrowWithCollateral(
            address(user), testMarkets[dai], testMarket, borrowed, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        uint256 promoted = _promoteBorrow(promoter1, testMarket, realBorrowed.wadMul(promotionFactor));

        uint256 expectedP2PBorrow = promoted;
        uint256 expectedPoolBorrow = realBorrowed.zeroFloorSub(promoted);

        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = snippets.marketBorrow(testMarket.underlying);

        assertApproxEqAbs(poolBorrowAmount, expectedPoolBorrow, 2, "Incorrect pool borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, expectedP2PBorrow, 2, "Incorrect P2P borrow amount");
    }

    function testUserHealthFactorShouldReturnMaxIfNoPosition(address user) public {
        user = _boundAddressNotZero(user);
        uint256 healthFactor = snippets.healthFactor(user);
        assertEq(type(uint256).max, healthFactor);
    }

    function testUserHealthFactor(
        uint256 collateralSeed,
        uint256 borrowableInEModeSeed,
        uint256 collateral,
        uint256 borrowed
    ) public {
        TestMarket storage collateralMarket = testMarkets[_randomCollateral(collateralSeed)];
        TestMarket storage borrowedMarket = testMarkets[_randomBorrowableInEMode(borrowableInEModeSeed)];

        collateral = _boundCollateral(collateralMarket, collateral, borrowedMarket);
        user.approve(collateralMarket.underlying, collateral);
        user.supplyCollateral(collateralMarket.underlying, collateral);

        borrowed = _boundBorrow(borrowedMarket, borrowed);
        borrowed = _borrowWithoutCollateral(
            address(user), borrowedMarket, borrowed, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        DataTypes.ReserveConfigurationMap memory collateralReserve = pool.getConfiguration(collateralMarket.underlying);
        collateral = (
            (morpho.collateralBalance(collateralMarket.underlying, address(user)))
                * (snippets.assetPrice(collateralMarket.underlying, collateralReserve.getEModeCategory()))
        ) / 10 ** collateralReserve.getDecimals();
        collateral = ((Constants.LT_LOWER_BOUND - 1) * collateral) / Constants.LT_LOWER_BOUND;
        uint256 expectedMaxDebt = collateral.percentMulDown(collateralMarket.lt);

        DataTypes.ReserveConfigurationMap memory borrowedReserve = pool.getConfiguration(borrowedMarket.underlying);

        uint256 expectedDebt = (
            (morpho.borrowBalance(borrowedMarket.underlying, address(user)))
                * (snippets.assetPrice(borrowedMarket.underlying, borrowedReserve.getEModeCategory()))
        ).divUp(10 ** borrowedReserve.getDecimals());
        uint256 expectedHealthFactor;

        if (expectedDebt > 0) {
            expectedHealthFactor = expectedMaxDebt.wadDiv(expectedDebt);
        } else {
            expectedHealthFactor = type(uint256).max;
        }

        uint256 returnedHealthFactor = snippets.healthFactor(address(user));
        assertApproxEqAbs(
            expectedHealthFactor.rayDiv(returnedHealthFactor), WadRayMath.RAY, 1, "Incorrect Health Factor"
        );
    }

    function testSupplyBalance(uint256 seed, uint256 amount, uint256 promotionFactor) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        amount = _boundSupply(testMarket, amount);
        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);
        uint256 promoted = _promoteSupply(promoter1, testMarket, amount.wadMul(promotionFactor));

        (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance) =
            snippets.supplyBalance(testMarket.underlying, address(user));

        assertApproxEqAbs(promoted, balanceInP2P, 2, "Incorrect P2P amount");
        assertApproxEqAbs(amount.zeroFloorSub(promoted), balanceOnPool, 2, "Incorrect pool amount");
        assertApproxEqAbs(amount, totalBalance, 3, "Incorrect total amount");
    }

    function testBorrowBalance(uint256 seed, uint256 amount, uint256 promotionFactor) public {
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        amount = _boundBorrow(testMarket, amount);

        uint256 promoted = _promoteBorrow(promoter1, testMarket, amount.wadMul(promotionFactor));

        amount = _borrowWithoutCollateral(
            address(user), testMarket, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        (uint256 balanceInP2P, uint256 balanceOnPool, uint256 totalBalance) =
            snippets.borrowBalance(testMarket.underlying, address(user));

        assertApproxEqAbs(promoted, balanceInP2P, 2, "Incorrect P2P amount");
        assertApproxEqAbs(amount.zeroFloorSub(promoted), balanceOnPool, 2, "Incorrect pool amount");
        assertApproxEqAbs(amount, totalBalance, 3, "Incorrect total amount");
    }

    function _computeSupplyRate(uint256 amount, uint256 promoted, address underlying)
        internal
        view
        returns (uint256 expectedRate)
    {
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: market.proportionIdle(),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pTotal: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        expectedRate = p2pSupplyRate.rayMul(promoted.rayDiv(amount))
            + poolSupplyRate.rayMul((amount.zeroFloorSub(promoted)).rayDiv(amount));
    }

    function _computeBorrowRate(uint256 amount, uint256 promoted, address underlying)
        internal
        view
        returns (uint256 expectedRate)
    {
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: market.deltas.borrow.scaledDelta,
                p2pTotal: market.deltas.borrow.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        expectedRate = p2pBorrowRate.rayMul(promoted.rayDiv(amount))
            + poolBorrowRate.rayMul((amount.zeroFloorSub(promoted)).rayDiv(amount));
    }
}
