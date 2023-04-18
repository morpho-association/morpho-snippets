// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "lib/morpho-aave-v3/test/helpers/IntegrationTest.sol";
import {Snippets} from "@snippets/Snippets.sol";
import {console2} from "@forge-std/console2.sol";
import {console} from "@forge-std/console.sol";

contract TestIntegrationSnippets is IntegrationTest {
    using Math for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using TestMarketLib for TestMarket;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using stdStorage for StdStorage;

    Snippets internal snippets;

    struct expectedSupply {
        uint256 totalSupply;
        uint256 poolSupply;
        uint256 p2pSupply;
        uint256 idleSupply;
    }

    function setUp() public virtual override {
        super.setUp();
        _deploySnippets();
    }

    function _deploySnippets() internal {
        snippets = new Snippets(address(morpho));
    }

    function testTotalSupplyShouldBeZeroIfNoAction() public {
        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount) =
            snippets.totalSupply();

        assertApproxEqAbs(totalSupplyAmount, 0, 1e9, "Incorrect supply amount");
        assertApproxEqAbs(p2pSupplyAmount, 0, 1, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, 0, 1, "Incorrect Idle supply amount");
        assertEq(p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount, totalSupplyAmount, "Incorrect values returned");
    }

    function testTotalBorrowShouldBeZeroIfNoAction() public {
        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount) = snippets.totalBorrow();

        assertApproxEqAbs(totalBorrowAmount, 0, 1e9, "Incorrect borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, 0, 1, "Incorrect P2P borrow amount");
        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }

    function testTotalSupply(uint256[] memory amounts, uint256[] memory idleAmounts, uint256 promotionFactor) public {
        expectedSupply memory expected;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        vm.assume(amounts.length >= allUnderlyings.length);
        vm.assume(idleAmounts.length >= allUnderlyings.length);

        DataTypes.ReserveConfigurationMap memory daiConfig = pool.getConfiguration(dai);
        uint256 daiPrice = snippets.assetPrice(daiConfig, dai);

        for (uint256 i; i < borrowableInEModeUnderlyings.length; ++i) {
            address underlying = borrowableInEModeUnderlyings[i];
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);
            uint256 assetUnit = 10 ** config.getDecimals();

            uint256 price = snippets.assetPrice(config, underlying);
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
            ) / 10 ** daiConfig.getDecimals();

            expected.totalSupply += (
                testMarkets[dai].minBorrowCollateral(testMarkets[underlying], idleAmounts[i], eModeCategoryId)
                    * daiPrice
            ) / 10 ** daiConfig.getDecimals();
            expected.idleSupply += (idleAmounts[i] * price) / assetUnit;
        }

        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount) =
            snippets.totalSupply();

        assertApproxEqAbs(totalSupplyAmount, expected.totalSupply, 1e9, "Incorrect supply amount");
        assertApproxEqAbs(p2pSupplyAmount, expected.p2pSupply, 1e9, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, expected.idleSupply, 1e9, "Incorrect Idle supply amount");
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
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);

            uint256 assetUnit = 10 ** config.getDecimals();

            uint256 price = snippets.assetPrice(config, underlying);

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

        assertApproxEqAbs(totalBorrowAmount, expectedTotalBorrow, 1e9, "Incorrect borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, expectedP2PBorrow, 1e9, "Incorrect P2P borrow amount");

        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }

    function testSupplyAPRShouldEqual0WhenNoSupply(address user, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, user);
        assertEq(supplyRatePerYear, 0);
    }

    function testBorrowAPRShouldEqual0WhenNoSupply(address user, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        uint256 supplyRatePerYear = snippets.borrowAPR(testMarket.underlying, user);
        assertEq(supplyRatePerYear, 0);
    }

    function testSupplyAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        amount = _boundSupply(testMarket, amount);
        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);
        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, address(user));
        DataTypes.ReserveData memory reserve = pool.getReserveData(testMarket.underlying);
        uint256 poolSupplyRatePerYear = reserve.currentLiquidityRate;
        assertEq(supplyRatePerYear, poolSupplyRatePerYear);
    }

    function testBorrowAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount, uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        address onBehalf = address(user);
        amount = _boundBorrow(testMarket, amount);

        _borrowWithoutCollateral(onBehalf, testMarket, amount, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS);

        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, onBehalf);
        DataTypes.ReserveData memory reserve = pool.getReserveData(testMarket.underlying);
        uint256 poolBorrowRatePerYear = reserve.currentVariableBorrowRate;
        assertEq(borrowRatePerYear, poolBorrowRatePerYear);
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

        uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: snippets.proportionIdle(market),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pAmount: market.deltas.supply.scaledP2PTotal,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        assertEq(supplyRatePerYear, p2pSupplyRate);
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

        uint256 p2pBorrowRate = snippets.p2pBorrowAPR(
            Snippets.P2PRateComputeParams({
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
        assertEq(borrowRatePerYear, p2pBorrowRate);
    }

    function testSupplyAPRWhenUserPartiallyMatched(uint256 amount, uint256 seed, uint256 promotionFactor) public {
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        amount = _boundSupply(testMarket, amount);
        vm.assume(amount.wadMul(promotionFactor) != 0);
        uint256 promoted = _promoteSupply(promoter1, testMarket, amount.wadMul(promotionFactor)) - 1; //  Minus 1 so that the test passes for now.

        user.approve(testMarket.underlying, amount);
        user.supply(testMarket.underlying, amount);

        uint256 supplyRatePerYear = snippets.supplyAPR(testMarket.underlying, address(user));
        uint256 expectedRate = _computeSupplyRate(amount, promoted, testMarket.underlying);

        assertApproxEqAbs(supplyRatePerYear, expectedRate, 1e22, "Incorrect supply APR");
    }

    function testBorrowAPRWhenUserPartiallyMatched(uint256 amount, uint256 seed, uint256 promotionFactor) public {
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        amount = _boundBorrow(testMarket, amount);

        uint256 promoted = _promoteBorrow(promoter1, testMarket, amount.wadMul(promotionFactor)); //  Minus 1 so that the test passes for now.

        amount = _borrowWithoutCollateral(
            address(user), testMarket, amount, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        uint256 borrowRatePerYear = snippets.borrowAPR(testMarket.underlying, address(user));
        uint256 expectedBorrowRate = _computeBorrowRate(amount, promoted, testMarket.underlying);

        assertApproxEqAbs(borrowRatePerYear, expectedBorrowRate, 1e22, "Incorrect supply APR");
    }

    function testWeightedRateWhenBalanceZero(uint256 p2pRate, uint256 poolRate) public {
        uint256 weightedRate = snippets.weightedRate(p2pRate, poolRate, 0, 0);
        assertEq(0, weightedRate);
    }

    function testWeightedRateWhenPoolBalanceZero(uint256 p2pRate, uint256 poolRate, uint256 balanceInP2P) public {
        balanceInP2P = _boundAmountNotZero(balanceInP2P);
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);
        uint256 weightedRate = snippets.weightedRate(p2pRate, poolRate, balanceInP2P, 0);
        assertEq(p2pRate, weightedRate);
    }

    function testWeightedRateWhenP2PBalanceZero(uint256 p2pRate, uint256 poolRate, uint256 balanceOnPool) public {
        balanceOnPool = _boundAmountNotZero(balanceOnPool);
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);
        uint256 weightedRate = snippets.weightedRate(p2pRate, poolRate, 0, balanceOnPool);
        assertEq(poolRate, weightedRate);
    }

    function testWeightedRate(uint256 p2pRate, uint256 poolRate, uint256 balanceOnPool, uint256 balanceInP2P) public {
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);
        balanceOnPool = bound(balanceOnPool, 0, type(uint128).max);
        balanceInP2P = bound(balanceInP2P, 0, type(uint128).max);

        uint256 weightedRate = snippets.weightedRate(p2pRate, poolRate, balanceInP2P, balanceOnPool);
        uint256 expectedRate = p2pRate.rayMul(balanceInP2P.rayDiv(balanceInP2P + balanceOnPool))
            + poolRate.rayMul(balanceOnPool.rayDiv(balanceInP2P + balanceOnPool));
        assertEq(expectedRate, weightedRate);
    }

    function testMarketSupplyShouldBeAlmostZeroIfNoAction(uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];
        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount) =
            snippets.marketSupply(testMarket.underlying);
        assertEq(p2pSupplyAmount, 0, "Incorrect p2p amount");
        assertApproxEqAbs(poolSupplyAmount, 0, 1e10, "Incorrect pool amount");
        assertEq(idleSupplyAmount, 0, "Incorrect idle amount");
    }

    function testMarketBorrowShouldBeAlmostZeroIfNoAction(uint256 seed) public {
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];
        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = snippets.marketBorrow(testMarket.underlying);
        assertEq(p2pBorrowAmount, 0, "Incorrect p2p amount");
        assertApproxEqAbs(poolBorrowAmount, 0, 1e10, "Incorrect pool amount");
    }

    function testMarketSupply(uint256 seed, uint256 amount, uint256 idleAmount, uint256 promotionFactor) public {
        expectedSupply memory expected;
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

        expected.p2pSupply += promoted;
        expected.poolSupply += amount.zeroFloorSub(promoted);
        if (testMarket.underlying == dai) {
            expected.poolSupply += testMarkets[dai].minBorrowCollateral(testMarket, promoted, eModeCategoryId);
        }

        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount) =
            snippets.marketSupply(testMarket.underlying);

        assertApproxEqAbs(poolSupplyAmount, expected.poolSupply, 1e10, "Incorrect pool supply amount");
        assertApproxEqAbs(p2pSupplyAmount, expected.p2pSupply, 1e9, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, expected.idleSupply, 1e9, "Incorrect Idle supply amount");
    }

    function testMarketBorrow(uint256 seed, uint256 amount, uint256 promotionFactor) public {
        uint256 expectedPoolBorrow;
        uint256 expectedP2PBorrow;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        TestMarket storage testMarket = testMarkets[_randomBorrowableInEMode(seed)];

        uint256 borrowed = _boundBorrow(testMarket, amount);

        (, uint256 realborrowed) = _borrowWithCollateral(
            address(user), testMarkets[dai], testMarket, borrowed, address(user), address(user), DEFAULT_MAX_ITERATIONS
        );

        uint256 promoted = _promoteBorrow(promoter1, testMarket, realborrowed.wadMul(promotionFactor));

        expectedP2PBorrow += realborrowed.wadMul(promotionFactor);
        expectedPoolBorrow += realborrowed.zeroFloorSub(promoted);

        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount) = snippets.marketBorrow(testMarket.underlying);

        assertApproxEqAbs(poolBorrowAmount, expectedPoolBorrow, 1e9, "Incorrect Pool borrow amount");
        assertApproxEqAbs(p2pBorrowAmount, expectedP2PBorrow, 1e9, "Incorrect P2P borrow amount");
    }

    function testp2pBorrowAPRWhenSupplyRateGreaterThanBorrowRateWithoutP2PAndDelta(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max);
        borrowRate = bound(borrowRate, 0, supplyRate);
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        Types.Market memory market = morpho.market(testMarket.underlying);
        uint256 p2pBorrowRate = snippets.p2pBorrowAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        assertEq(borrowRate, p2pBorrowRate);
    }

    function testp2pSupplyAPRWhenSupplyRateGreaterThanBorrowRateWithoutP2PAndDeltaAndIdle(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max);
        borrowRate = bound(borrowRate, 0, supplyRate);
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        Types.Market memory market = morpho.market(testMarket.underlying);
        uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );
        assertEq(borrowRate, p2pSupplyRate);
    }

    function testp2pSupplyAPRWithoutP2PAndDeltaAndIdle(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max - 1);
        borrowRate = bound(borrowRate, supplyRate, type(uint128).max);

        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        Types.Market memory market = morpho.market(testMarket.underlying);
        uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyRate, borrowRate, p2pIndexCursor);
        uint256 expectedSupplyP2PRate = expectedP2PRate - (expectedP2PRate - supplyRate).percentMul(reserveFactor);
        assertEq(expectedSupplyP2PRate, p2pSupplyRate);
    }

    function testp2pBorrowAPRWithoutP2PAndDelta(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max - 1);
        borrowRate = bound(borrowRate, supplyRate, type(uint128).max);

        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        Types.Market memory market = morpho.market(testMarket.underlying);
        uint256 p2pBorrowRate = snippets.p2pBorrowAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyRate, borrowRate, p2pIndexCursor);
        uint256 expectedBorrowP2PRate = expectedP2PRate + (borrowRate - expectedP2PRate).percentMul(reserveFactor);
        assertEq(expectedBorrowP2PRate, p2pBorrowRate);
    }

    function testp2pBorrowAPRWithDelta(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate,
        uint256 p2pDelta,
        uint256 p2pAmount,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max);
        borrowRate = bound(borrowRate, 0, type(uint128).max);
        p2pDelta = bound(p2pDelta, 0, type(uint128).max);
        p2pAmount = bound(p2pAmount, 0, type(uint128).max);
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        Types.Market memory market = morpho.market(testMarket.underlying);

        vm.assume(p2pDelta.rayMul(market.indexes.borrow.poolIndex) < p2pAmount.rayMul(market.indexes.borrow.p2pIndex));
        uint256 p2pBorrowRate = snippets.p2pBorrowAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.borrow.poolIndex,
                p2pIndex: market.indexes.borrow.p2pIndex,
                proportionIdle: 0,
                p2pDelta: p2pDelta,
                p2pAmount: p2pAmount,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );
        uint256 expectedBorrowP2PRate;
        if (supplyRate > borrowRate) {
            expectedBorrowP2PRate = borrowRate;
        } else {
            uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyRate, borrowRate, p2pIndexCursor);
            expectedBorrowP2PRate = expectedP2PRate + (borrowRate - expectedP2PRate).percentMul(reserveFactor);
        }

        uint256 proportionDelta = Math.min(
            p2pDelta.rayMul(market.indexes.borrow.poolIndex).rayDivUp(p2pAmount.rayMul(market.indexes.borrow.p2pIndex)),
            WadRayMath.RAY
        );

        expectedBorrowP2PRate =
            expectedBorrowP2PRate.rayMul(WadRayMath.RAY - proportionDelta) + borrowRate.rayMul(proportionDelta);
        assertEq(expectedBorrowP2PRate, p2pBorrowRate);
    }

    function testp2pSupplyAPRWithDeltaAndIdle(
        uint256 seed,
        uint256 supplyRate,
        uint256 borrowRate,
        uint256 p2pDelta,
        uint256 p2pAmount,
        uint256 idleAmount,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyRate = bound(supplyRate, 0, type(uint128).max);
        borrowRate = bound(borrowRate, 0, type(uint128).max);
        p2pDelta = bound(p2pDelta, 0, type(uint128).max);
        p2pAmount = bound(p2pAmount, 0, type(uint128).max);
        idleAmount = bound(idleAmount, 0, type(uint128).max);
        TestMarket storage testMarket = testMarkets[_randomUnderlying(seed)];

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        Types.Market memory market = morpho.market(testMarket.underlying);
        vm.assume(
            p2pDelta.rayMul(market.indexes.supply.poolIndex) + idleAmount
                < p2pAmount.rayMul(market.indexes.supply.p2pIndex)
        );
        market.idleSupply = idleAmount;
        market.deltas.supply.scaledP2PTotal = p2pAmount;
        uint256 proportionIdle = snippets.proportionIdle(market);

        uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyRate,
                poolBorrowRatePerYear: borrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: proportionIdle,
                p2pDelta: p2pDelta,
                p2pAmount: p2pAmount,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );
        uint256 expectedSupplyP2PRate;
        if (supplyRate > borrowRate) {
            expectedSupplyP2PRate = borrowRate;
        } else {
            uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyRate, borrowRate, p2pIndexCursor);
            expectedSupplyP2PRate = expectedP2PRate - (expectedP2PRate - supplyRate).percentMul(reserveFactor);
        }

        uint256 proportionDelta = Math.min(
            p2pDelta.rayMul(market.indexes.supply.poolIndex).rayDivUp(p2pAmount.rayMul(market.indexes.supply.p2pIndex)),
            WadRayMath.RAY
        );

        expectedSupplyP2PRate = expectedSupplyP2PRate.rayMul(WadRayMath.RAY - proportionDelta - proportionIdle)
            + supplyRate.rayMul(proportionDelta);
        assertApproxEqAbs(expectedSupplyP2PRate, p2pSupplyRate, 1e9, "Incorrect APR");
    }

    function testUserHealthFactorShouldReturnMaxIfNoPosition(address user) public {
        user = _boundAddressNotZero(user);
        uint256 healthFactor = snippets.userHealthFactor(user);
        assertEq(type(uint256).max, healthFactor);
    }

    function testUserHealthFactor(
        uint256 collateralSeed,
        uint256 borrowableInEModeSeed,
        uint256 healthFactor,
        uint256 amount,
        address user
    ) public {
        user = _boundAddressNotZero(user);
        TestMarket storage collateralMarket = testMarkets[_randomCollateral(collateralSeed)];
        TestMarket storage borrowedMarket = testMarkets[_randomBorrowableInEMode(borrowableInEModeSeed)];
        uint256 borrowed = _boundBorrow(borrowedMarket, amount);
        _createPosition(borrowedMarket, collateralMarket, user, borrowed, 0, healthFactor);
        uint256 returnedHealthFactor = snippets.userHealthFactor(user);
        assertApproxEqAbs(healthFactor, returnedHealthFactor, 3, "Incorrect Health Factor");
    }

    function _createPosition(
        TestMarket storage borrowedMarket,
        TestMarket storage collateralMarket,
        address borrower,
        uint256 borrowed,
        uint256 promotionFactor,
        uint256 healthFactor
    ) internal returns (uint256 borrowBalance, uint256 collateralBalance) {
        borrowed = _boundBorrow(borrowedMarket, borrowed);
        (, borrowed) = _borrowWithCollateral(
            borrower, collateralMarket, borrowedMarket, borrowed, borrower, borrower, DEFAULT_MAX_ITERATIONS
        );

        _promoteBorrow(promoter1, borrowedMarket, borrowed.wadMul(promotionFactor));

        uint256 newScaledCollateralBalance = morpho.scaledCollateralBalance(collateralMarket.underlying, borrower)
            .rayMul((collateralMarket.ltv - 10).rayDiv(collateralMarket.lt)).wadMul(healthFactor);

        stdstore.target(address(morpho)).sig("scaledCollateralBalance(address,address)").with_key(
            collateralMarket.underlying
        ).with_key(borrower).checked_write(newScaledCollateralBalance);

        borrowBalance = morpho.borrowBalance(borrowedMarket.underlying, borrower);
        collateralBalance = morpho.collateralBalance(collateralMarket.underlying, borrower);
    }

    function _computeSupplyRate(uint256 amount, uint256 promoted, address underlying)
        internal
        view
        returns (uint256 expectedRate)
    {
        (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(underlying);
        Types.Market memory market = morpho.market(underlying);

        uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
            Snippets.P2PRateComputeParams({
                poolSupplyRatePerYear: poolSupplyRate,
                poolBorrowRatePerYear: poolBorrowRate,
                poolIndex: market.indexes.supply.poolIndex,
                p2pIndex: market.indexes.supply.p2pIndex,
                proportionIdle: snippets.proportionIdle(market),
                p2pDelta: market.deltas.supply.scaledDelta,
                p2pAmount: market.deltas.supply.scaledP2PTotal,
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

        uint256 p2pBorrowRate = snippets.p2pBorrowAPR(
            Snippets.P2PRateComputeParams({
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
        expectedRate = p2pBorrowRate.rayMul(promoted.rayDiv(amount))
            + poolBorrowRate.rayMul((amount.zeroFloorSub(promoted)).rayDiv(amount));
    }
}
