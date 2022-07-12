// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './interfaces/IOSWAP_RestrictedLiquidityProvider2.sol';
import './interfaces/IOSWAP_RestrictedPair3.sol';
import './OSWAP_RestrictedLiquidityProvider.sol';

contract OSWAP_RestrictedLiquidityProvider2 is OSWAP_RestrictedLiquidityProvider, IOSWAP_RestrictedLiquidityProvider2 {
    constructor(address _factory, address _WETH) public 
        OSWAP_RestrictedLiquidityProvider(_factory, _WETH)
    {
    }
    
    function addLiquidityWithFee(
        // 0: address tokenA,
        // 1: address tokenB,
        // 2: bool addingTokenA,
        // 3: uint256 pairIndex,
        // 4: uint256 offerIndex,
        // 5: uint256 amountIn,
        // 6: bool allowAll,
        // 7: uint256 restrictedPrice,
        // 8: uint256 startDate,
        // 9: uint256 expire,
        // 10: uint256 deadline
        uint256[11] calldata param,
        uint256 feeIn
    ) public virtual override ensure(param[10]) returns (address pair, uint256 _offerIndex) {
        address tokenA = address(bytes20(bytes32(param[0]<<96)));
        address tokenB = address(bytes20(bytes32(param[1]<<96)));
        pair = _getPair(tokenA, tokenB, param[3]);

        bool addingTokenA = param[2]==1;
        bool direction = (tokenA < tokenB) ? !addingTokenA : addingTokenA;

        TransferHelper.safeTransferFrom(govToken, msg.sender, pair, feeIn);
        if (param[4] == 0) {
            _offerIndex = IOSWAP_RestrictedPair3(pair).createOrderWithPrepaidFee(msg.sender, direction, param[6]==1, param[7], param[8], param[9], feeIn);
        } else {
            _offerIndex = param[4];
            _checkOrder(pair, direction, _offerIndex, param[6]==1, param[7], param[8], param[9]);
            IOSWAP_RestrictedPair3(pair).addPrepaidFee(msg.sender, direction, _offerIndex, feeIn);
        }

        if (param[5] > 0) {
            TransferHelper.safeTransferFrom(addingTokenA ? tokenA : tokenB, msg.sender, pair, param[5]);
            IOSWAP_RestrictedPair3(pair).addLiquidity(direction, _offerIndex);
        }
    }
    function addLiquidityETHWithFee(
        // 0: address tokenA,
        // 1: bool addingTokenA,
        // 2: uint256 pairIndex,
        // 3: uint256 offerIndex,
        // 4: uint256 amountAIn,
        // 5: bool allowAll,
        // 6: uint256 restrictedPrice,
        // 7: uint256 startDate,
        // 8: uint256 expire,
        // 9: uint256 deadline
        uint256[10] calldata param,
        uint256 feeIn
    ) public virtual override payable ensure(param[9]) returns (address pair, uint256 _offerIndex) {
        address tokenA = address(bytes20(bytes32(param[0]<<96)));
        pair = _getPair(tokenA, WETH, param[2]);

        bool addingTokenA = param[1]==1;
        bool direction = (tokenA < WETH) ? !addingTokenA : addingTokenA;

        TransferHelper.safeTransferFrom(govToken, msg.sender, pair, feeIn);
        if (param[3] == 0) {
            _offerIndex = IOSWAP_RestrictedPair3(pair).createOrderWithPrepaidFee(msg.sender, direction, param[5]==1, param[6], param[7], param[8], feeIn);
        } else {
            _offerIndex = param[3];
            _checkOrder(pair, direction, _offerIndex, param[5]==1, param[6], param[7], param[8]);
            IOSWAP_RestrictedPair3(pair).addPrepaidFee(msg.sender, direction, _offerIndex, feeIn);
        }

        if (addingTokenA) {
            if (param[4] > 0)
                TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, param[4]);
        } else {
            uint256 ETHIn = msg.value;
            IWETH(WETH).deposit{value: ETHIn}();
            require(IWETH(WETH).transfer(pair, ETHIn), 'Transfer failed');
        }
        if (param[4] > 0 || msg.value > 0)
            IOSWAP_RestrictedPair3(pair).addLiquidity(direction, _offerIndex);
    }
}
