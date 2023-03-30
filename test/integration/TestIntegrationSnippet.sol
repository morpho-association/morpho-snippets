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

    Snippets internal snippets;

    function setUp() public virtual override {
        super.setUp();
        _deploySnippets();
    }

    function _deploySnippets() internal {
        snippets = new Snippets(address(morpho));
    }

    function testTotalSupply(uint256[] memory amounts, uint256[] memory idleAmounts) public {
        uint256 expectedTotalSupply;s

        vm.assume(amounts.length >= allUnderlyings.length);
        vm.assume(idleAmounts.length >= allUnderlyings.length);

        for (uint256 i; i < allUnderlyings.length; ++i) {
            address underlying = allUnderlyings[i];
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);
            uint256 assetUnit = 10 ** config.getDecimals();

            uint256 price = snippets.assetPrice(config, underlying);
            uint256 amount = _boundSupply(testMarkets[underlying], amounts[i]);

            user.approve(underlying, amount);
            user.supply(underlying, amount);

            expectedTotalSupply += (amount * price) / assetUnit;
        }

        (uint256 p2pSupplyAmount, uint256 poolSupplyAmount, uint256 idleSupplyAmount, uint256 totalSupplyAmount) =
            snippets.totalSupply();

        assertApproxEqAbs(totalSupplyAmount, expectedTotalSupply, 1e9, "Incorrect supply amount");

        assertEq(p2pSupplyAmount + poolSupplyAmount + idleSupplyAmount, totalSupplyAmount, "Incorrect values returned");
    }

    function testTotalBorrow(uint256[15] memory amounts, uint256[15] memory idleAmounts, uint256 promotionFactor)
        public
    {
        uint256 expectedTotalBorrow;
        uint256 expectedP2PBorrow;
        promotionFactor = bound(promotionFactor, 0, WadRayMath.WAD);
        vm.assume(amounts.length >= borrowableUnderlyings.length);
        vm.assume(idleAmounts.length >= borrowableUnderlyings.length);

        for (uint256 i; i < borrowableUnderlyings.length; ++i) {
            address underlying = borrowableUnderlyings[i];
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(underlying);

            uint256 assetUnit = 10 ** config.getDecimals();

            uint256 price = snippets.assetPrice(config, underlying);

            uint256 borrowed = _boundBorrow(testMarkets[underlying], amounts[i]);

            if (underlying != dai) {
                _deal(underlying, address(promoter1), borrowed.percentMul(promotionFactor));
                _promoteBorrow(promoter1, testMarkets[underlying], borrowed.percentMul(promotionFactor));
                
                (, uint256 realborrowed) = _borrowWithCollateral(
                    address(user),
                    testMarkets[dai],
                    testMarkets[underlying],
                    borrowed,
                    address(user),
                    address(user),
                    DEFAULT_MAX_ITERATIONS
                );
                expectedP2PBorrow += (borrowed.percentMul(promotionFactor) * price) / assetUnit;
                expectedTotalBorrow += (borrowed * price) / assetUnit;
            }
        }

        (uint256 p2pBorrowAmount, uint256 poolBorrowAmount, uint256 totalBorrowAmount) = snippets.totalBorrow();

        assertApproxEqAbs(totalBorrowAmount, expectedTotalBorrow, 1e9, "Incorrect borrow amount");

        assertEq(p2pBorrowAmount + poolBorrowAmount, totalBorrowAmount, "Incorrect values returned");
    }
}
