// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './IOSWAP_RestrictedPairPrepaidFee.sol';

interface IOSWAP_RestrictedPair3 is IOSWAP_RestrictedPairPrepaidFee {


    // function prepaidFeeBalance(bool direction, uint256 i) external view returns (uint balance);

    // function createOrderWithPrepaidFee(address provider, bool direction, bool allowAll, uint256 restrictedPrice, uint256 startDate, uint256 expire, uint feeIn) external returns (uint256 index);
    // function addPrepaidFee(address provider, bool direction, uint256 index, uint256 feeIn) external;

    function setApprovedTraderBySignature(bool direction, uint256 offerIndex, address trader, uint256 allocation, bytes calldata signature) external;

}