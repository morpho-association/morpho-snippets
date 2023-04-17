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
    using Snippets for Snippets.P2PRateComputeParams;

    Snippets internal snippets;

    struct expectedSupply {
        uint256 totalSupply;
        uint256 p2pSupply;
        uint256 idleSupply;
    }

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

        assertApproxEqAbs(totalSupplyAmount, 0, 1, "Incorrect supply amount");
        assertApproxEqAbs(p2pSupplyAmount, 0, 1, "Incorrect P2P supply amount");
        assertApproxEqAbs(idleSupplyAmount, 0, 1, "Incorrect P2P supply amount");
        assertEq(p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount, totalSupplyAmount, "Incorrect values returned");
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
        assertApproxEqAbs(idleSupplyAmount, expected.idleSupply, 1e9, "Incorrect P2P supply amount");
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

            if (underlying != dai) {
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
        }

        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount) = snippets.totalBorrow();

        assertApproxEqAbs(totalBorrowAmount, expectedTotalBorrow, 1e9, "Incorrect borrow amount");

        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }

    function testSupplyAPRShouldEqual0WhenNoSupply(address user) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            uint256 supplyRatePerYear = snippets.supplyAPR(allUnderlyings[i], user);
            assertEq(supplyRatePerYear, 0);
        }
    }

    function testBorrowAPRShouldEqual0WhenNoSupply(address user) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            uint256 supplyRatePerYear = snippets.borrowAPR(allUnderlyings[i], user);
            assertEq(supplyRatePerYear, 0);
        }
    }

    function testSupplyAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            amount = _boundSupply(testMarkets[underlying], amount);
            user.approve(underlying, amount);
            user.supply(underlying, amount);
            uint256 supplyRatePerYear = snippets.supplyAPR(underlying, address(user));
            DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
            uint256 poolSupplyRatePerYear = reserve.currentLiquidityRate;
            assertEq(supplyRatePerYear, poolSupplyRatePerYear);
        }
    }

    function testBorrowAPRUserRateShouldMatchPoolRateWhenNoMatch(uint256 amount) public {
        for (uint256 i; i < borrowableInEModeUnderlyings.length; ++i) {
            address underlying = borrowableInEModeUnderlyings[i];
            address onBehalf = address(user);
            vm.assume(amount > 10);

            uint256 borrowed = _borrowWithoutCollateral(
                onBehalf, testMarkets[underlying], amount, onBehalf, onBehalf, DEFAULT_MAX_ITERATIONS
            );
            (uint256 balanceInP2P, uint256 balanceOnPool,) = snippets.borrowBalance(underlying, onBehalf);

            uint256 borrowRatePerYear = snippets.borrowAPR(underlying, onBehalf);
            DataTypes.ReserveData memory reserve = pool.getReserveData(underlying);
            uint256 poolBorrowRatePerYear = reserve.currentVariableBorrowRate;
            assertEq(borrowRatePerYear, poolBorrowRatePerYear);
        }
    }

    function testSupplyAPRUserRateShouldMatchP2PRateWhenFullyMatched(uint256 amount) public {
        for (uint256 i; i < borrowableInEModeUnderlyings.length; ++i) {
            address underlying = borrowableInEModeUnderlyings[i];
            address onBehalf = address(user);

            amount = _boundSupply(testMarkets[underlying], amount);

            amount = _promoteSupply(promoter1, testMarkets[underlying], amount);

            user.approve(underlying, amount);
            user.supply(underlying, amount);

            uint256 supplyRatePerYear = snippets.supplyAPR(underlying, onBehalf);
            (uint256 poolSupplyRate, uint256 poolBorrowRate) = snippets.poolAPR(underlying);
            Types.Market memory market = morpho.market(underlying);

            uint256 p2pSupplyRate = snippets.p2pSupplyAPR(
                P2PRateComputeParams({
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
    }
}
