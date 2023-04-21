// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "lib/morpho-aave-v3/test/helpers/BaseTest.sol";
import {Utils} from "@snippets/Utils.sol";

/// @notice Didn't test the proportionIdle function as it is the same in Morpho Contract.
contract TestUnitSnippets is BaseTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    function testWeightedRateWhenBalanceZero(uint256 p2pRate, uint256 poolRate) public {
        uint256 weightedRate = Utils.weightedRate(p2pRate, poolRate, 0, 0);

        assertEq(0, weightedRate, "Incorrect rate");
    }

    function testWeightedRateWhenPoolBalanceZero(uint256 p2pRate, uint256 poolRate, uint256 balanceInP2P) public {
        balanceInP2P = _boundAmountNotZero(balanceInP2P);
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);

        uint256 weightedRate = Utils.weightedRate(p2pRate, poolRate, balanceInP2P, 0);

        assertEq(p2pRate, weightedRate, "Incorrect rate");
    }

    function testWeightedRateWhenP2PBalanceZero(uint256 p2pRate, uint256 poolRate, uint256 balanceOnPool) public {
        balanceOnPool = _boundAmountNotZero(balanceOnPool);
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);

        uint256 weightedRate = Utils.weightedRate(p2pRate, poolRate, 0, balanceOnPool);

        assertEq(poolRate, weightedRate, "Incorrect rate");
    }

    function testWeightedRate(uint256 p2pRate, uint256 poolRate, uint256 balanceOnPool, uint256 balanceInP2P) public {
        poolRate = bound(poolRate, 0, type(uint96).max);
        p2pRate = bound(p2pRate, 0, type(uint96).max);
        balanceOnPool = bound(balanceOnPool, 1, type(uint128).max);
        balanceInP2P = bound(balanceInP2P, 1, type(uint128).max);

        uint256 weightedRate = Utils.weightedRate(p2pRate, poolRate, balanceInP2P, balanceOnPool);
        uint256 expectedRate = p2pRate.rayMul(balanceInP2P.rayDiv(balanceInP2P + balanceOnPool))
            + poolRate.rayMul(balanceOnPool.rayDiv(balanceInP2P + balanceOnPool));

        assertEq(expectedRate, weightedRate, "Incorrect rate");
    }

    function testP2PSupplyAPRWhenSupplyRateGreaterThanBorrowRateWithoutP2PAndDeltaAndIdle(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint256 poolIndex,
        uint256 p2pIndex,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max);
        borrowPoolRate = bound(borrowPoolRate, 0, supplyPoolRate);
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );
        assertEq(borrowPoolRate, p2pSupplyRate, "Incorrect P2P APR");
    }

    function testP2PBorrowAPRWhenSupplyRateGreaterThanBorrowRateWithoutP2PAndDelta(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint256 poolIndex,
        uint256 p2pIndex,
        uint16 reserveFactor,
        uint16 p2pIndexCursor
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max);
        borrowPoolRate = bound(borrowPoolRate, 0, supplyPoolRate);
        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );
        assertEq(borrowPoolRate, p2pBorrowRate, "Incorrect P2P APR");
    }

    function testP2PSupplyAPRWithoutP2PAndDeltaAndIdle(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint16 reserveFactor,
        uint16 p2pIndexCursor,
        uint256 poolIndex,
        uint256 p2pIndex
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max - 1);
        borrowPoolRate = bound(borrowPoolRate, supplyPoolRate, type(uint128).max);

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyPoolRate, borrowPoolRate, p2pIndexCursor);
        uint256 expectedSupplyP2PRate = expectedP2PRate - (expectedP2PRate - supplyPoolRate).percentMul(reserveFactor);
        assertEq(expectedSupplyP2PRate, p2pSupplyRate, "Incorrect P2P APR");
    }

    function testP2PBorrowAPRWithoutP2PAndDelta(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint16 reserveFactor,
        uint16 p2pIndexCursor,
        uint256 poolIndex,
        uint256 p2pIndex
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max - 1);
        borrowPoolRate = bound(borrowPoolRate, supplyPoolRate, type(uint128).max);

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: 0,
                p2pDelta: 0,
                p2pAmount: 0,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyPoolRate, borrowPoolRate, p2pIndexCursor);
        uint256 expectedBorrowP2PRate = expectedP2PRate + (borrowPoolRate - expectedP2PRate).percentMul(reserveFactor);

        assertEq(expectedBorrowP2PRate, p2pBorrowRate, "Incorrect P2P APR");
    }

    function testP2PBorrowAPRWithDelta(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint256 p2pDelta,
        uint256 p2pAmount,
        uint16 reserveFactor,
        uint16 p2pIndexCursor,
        uint256 poolIndex,
        uint256 p2pIndex
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max);
        borrowPoolRate = bound(borrowPoolRate, 0, type(uint128).max);
        poolIndex = bound(poolIndex, 0, type(uint96).max);
        p2pIndex = bound(p2pIndex, 0, type(uint96).max);
        p2pDelta = bound(p2pDelta, 0, type(uint128).max);
        p2pAmount = bound(p2pAmount, 0, type(uint128).max);

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        vm.assume(p2pDelta.rayMul(poolIndex) < p2pAmount.rayMul(p2pIndex));

        uint256 p2pBorrowRate = Utils.p2pBorrowAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: 0,
                p2pDelta: p2pDelta,
                p2pAmount: p2pAmount,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedBorrowP2PRate;
        if (supplyPoolRate > borrowPoolRate) {
            expectedBorrowP2PRate = borrowPoolRate;
        } else {
            uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyPoolRate, borrowPoolRate, p2pIndexCursor);
            expectedBorrowP2PRate = expectedP2PRate + (borrowPoolRate - expectedP2PRate).percentMul(reserveFactor);
        }

        uint256 proportionDelta =
            Math.min(p2pDelta.rayMul(poolIndex).rayDivUp(p2pAmount.rayMul(p2pIndex)), WadRayMath.RAY);
        expectedBorrowP2PRate =
            expectedBorrowP2PRate.rayMul(WadRayMath.RAY - proportionDelta) + borrowPoolRate.rayMul(proportionDelta);

        assertEq(expectedBorrowP2PRate, p2pBorrowRate, "Incorrect P2P APR");
    }

    function testP2PSupplyAPRWithDeltaAndIdle(
        uint256 supplyPoolRate,
        uint256 borrowPoolRate,
        uint256 p2pDelta,
        uint256 p2pAmount,
        uint256 idleAmount,
        uint16 reserveFactor,
        uint16 p2pIndexCursor,
        uint256 poolIndex,
        uint256 p2pIndex
    ) public {
        supplyPoolRate = bound(supplyPoolRate, 0, type(uint128).max);
        borrowPoolRate = bound(borrowPoolRate, 0, type(uint128).max);
        poolIndex = bound(poolIndex, 0, type(uint96).max);
        p2pIndex = bound(p2pIndex, 0, type(uint96).max);
        p2pDelta = bound(p2pDelta, 0, type(uint128).max);
        p2pAmount = bound(p2pAmount, 0, type(uint128).max);
        idleAmount = bound(idleAmount, 0, type(uint128).max);

        reserveFactor = uint16(bound(reserveFactor, 0, PercentageMath.PERCENTAGE_FACTOR));
        p2pIndexCursor = uint16(bound(p2pIndexCursor, 0, PercentageMath.PERCENTAGE_FACTOR));

        vm.assume(p2pDelta.rayMul(poolIndex) + idleAmount < p2pAmount.rayMul(p2pIndex));

        uint256 proportionIdle = Math.min(idleAmount.rayDivUp(p2pAmount.rayMul(p2pIndex)), WadRayMath.RAY);

        uint256 p2pSupplyRate = Utils.p2pSupplyAPR(
            Utils.P2PRateComputeParams({
                poolSupplyRatePerYear: supplyPoolRate,
                poolBorrowRatePerYear: borrowPoolRate,
                poolIndex: poolIndex,
                p2pIndex: p2pIndex,
                proportionIdle: proportionIdle,
                p2pDelta: p2pDelta,
                p2pAmount: p2pAmount,
                p2pIndexCursor: p2pIndexCursor,
                reserveFactor: reserveFactor
            })
        );

        uint256 expectedSupplyP2PRate;
        if (supplyPoolRate > borrowPoolRate) {
            expectedSupplyP2PRate = borrowPoolRate;
        } else {
            uint256 expectedP2PRate = PercentageMath.weightedAvg(supplyPoolRate, borrowPoolRate, p2pIndexCursor);
            expectedSupplyP2PRate = expectedP2PRate - (expectedP2PRate - supplyPoolRate).percentMul(reserveFactor);
        }

        uint256 proportionDelta =
            Math.min(p2pDelta.rayMul(poolIndex).rayDivUp(p2pAmount.rayMul(p2pIndex)), WadRayMath.RAY - proportionIdle);
        expectedSupplyP2PRate = expectedSupplyP2PRate.rayMul(WadRayMath.RAY - proportionDelta - proportionIdle)
            + supplyPoolRate.rayMul(proportionDelta);

        assertApproxEqAbs(expectedSupplyP2PRate, p2pSupplyRate, 1, "Incorrect P2P APR");
    }
}
