// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import "./IOSWAP_RestrictedLiquidityProvider.sol";

interface IOSWAP_RestrictedLiquidityProvider2 is IOSWAP_RestrictedLiquidityProvider {
    function addLiquidityWithFee(
        uint256[11] calldata param,
        uint256 feeIn
    ) external returns (address pair, uint256 _offerIndex);
    function addLiquidityETHWithFee(
        uint256[10] calldata param,
        uint256 feeIn
    ) external payable returns (address pair, uint256 _offerIndex);
}
