// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './interfaces/IOSWAP_RestrictedPair.sol';
import '../interfaces/IERC20.sol';
import '../libraries/SafeMath.sol';
import '../libraries/Address.sol';
import './interfaces/IOSWAP_RestrictedFactory.sol';
import '../oracle/interfaces/IOSWAP_OracleFactory.sol';
import '../gov/interfaces/IOAXDEX_Governance.sol';
import './interfaces/IOSWAP_ConfigStore.sol';
import '../oracle/interfaces/IOSWAP_OracleAdaptor2.sol';
import '../commons/OSWAP_PausablePair.sol';

contract OSWAP_RestrictedPair2 is IOSWAP_RestrictedPair, OSWAP_PausablePair  {
    using SafeMath for uint256;

    uint256 constant FEE_BASE = 10 ** 5;
    uint256 constant FEE_BASE_SQ = (10 ** 5) ** 2;
    uint256 constant WEI = 10**18;

    bytes32 constant FEE_PER_ORDER = "RestrictedPair.feePerOrder";
    bytes32 constant FEE_PER_TRADER = "RestrictedPair.feePerTrader";
    bytes32 constant MAX_DUR = "RestrictedPair.maxDur";
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    mapping(bool => uint256) public override counter;
    mapping(bool => Offer[]) public override offers;
    mapping(bool => mapping(address => uint256[])) public override providerOfferIndex;

    mapping(bool => mapping(uint256 => address[])) public override approvedTrader;
    mapping(bool => mapping(uint256 => mapping(address => bool))) public override isApprovedTrader;
    mapping(bool => mapping(uint256 => mapping(address => uint256))) public override traderAllocation;
    mapping(bool => mapping(address => uint256[])) public traderOffer;

    address public override immutable governance;
    address public override immutable whitelistFactory;
    address public override immutable restrictedLiquidityProvider;
    address public override immutable govToken;
    address public override immutable configStore;
    address public override token0;
    address public override token1;
    bool public override scaleDirection;
    uint256 public override scaler;

    uint256 public override lastGovBalance;
    uint256 public override lastToken0Balance;
    uint256 public override lastToken1Balance;
    uint256 public override protocolFeeBalance0;
    uint256 public override protocolFeeBalance1;
    uint256 public override feeBalance;

    constructor() public {
        (address _governance, address _whitelistFactory, address _restrictedLiquidityProvider, address _configStore) = IOSWAP_RestrictedFactory(msg.sender).getCreateAddresses();
        governance = _governance;
        whitelistFactory = _whitelistFactory;
        govToken = IOAXDEX_Governance(_governance).oaxToken();
        restrictedLiquidityProvider = _restrictedLiquidityProvider;
        configStore = _configStore;

        offers[true].push(Offer({
            provider: address(this),
            locked: true,
            feePaid: 0,
            amount: 0,
            receiving: 0,
            restrictedPrice: 0,
            startDate: 0,
            expire: 0
        }));
        offers[false].push(Offer({
            provider: address(this),
            locked: true,
            feePaid: 0,
            amount: 0,
            receiving: 0,
            restrictedPrice: 0,
            startDate: 0,
            expire: 0
        }));
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, 'FORBIDDEN'); // sufficient check

        token0 = _token0;
        token1 = _token1;
        require(token0 < token1, "Invalid token pair order"); 
        address oracle = IOSWAP_RestrictedFactory(factory).oracles(token0, token1);
        require(oracle != address(0), "No oracle found");

        uint8 token0Decimals = IERC20(token0).decimals();
        uint8 token1Decimals = IERC20(token1).decimals();
        if (token0Decimals == token1Decimals) {
            scaler = 1;
        } else {
            scaleDirection = token1Decimals > token0Decimals;
            scaler = 10 ** uint256(scaleDirection ? (token1Decimals - token0Decimals) : (token0Decimals - token1Decimals));
        }
    }

    function getOffers(bool direction, uint256 start, uint256 length) external override view returns (uint256[] memory index, address[] memory provider, bool[] memory locked, uint256[] memory feePaidAndReceiving, uint256[] memory amountAndPrice, uint256[] memory startDateAndExpire) {
        return _showList(0, address(0), direction, start, length);
    }

    function getLastBalances() external view override returns (uint256, uint256) {
        return (
            lastToken0Balance,
            lastToken1Balance
        );
    }
    function getBalances() public view override returns (uint256, uint256, uint256) {
        return (
            IERC20(govToken).balanceOf(address(this)),
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TRANSFER_FAILED');
    }
    function _getMaxOut(bool direction, uint256 offerIdx, address trader) internal view returns (uint256 output) {
        uint256 offerAmount =  offers[direction][offerIdx].amount;
        uint256 alloc = traderAllocation[direction][offerIdx][trader];
        output = alloc < offerAmount ? alloc : offerAmount;
    }
    function _getInputFromOutput(address trader, bool direction, address oracle, uint256 offerIdx, uint256 amountOut) internal view returns (uint256 amountIn, uint256 numerator, uint256 denominator) {
        bytes memory data2 = abi.encodePacked(offerIdx);
        (numerator, denominator) = IOSWAP_OracleAdaptor2(oracle).getRatio(direction ? token0 : token1, direction ? token0 : token1, 0, amountOut, trader, data2);
        amountIn = amountOut.mul(denominator);
        if (scaler > 1)
            amountIn = (direction != scaleDirection) ? amountIn.mul(scaler) : amountIn.div(scaler);
        amountIn = amountIn.div(numerator);
    }
    function _oneOutput(uint256 amountIn, address trader, bool direction, uint256 offerIdx, address oracle, uint256 tradeFee) internal view returns (uint256 amountInPlusFee, uint256 output, uint256 tradeFeeCollected, uint256 price) {
        output = _getMaxOut(direction, offerIdx, trader);

        uint256 numerator; uint256 denominator;
        (amountInPlusFee, numerator, denominator) = _getInputFromOutput(trader, direction, oracle, offerIdx, output);

        tradeFeeCollected = amountInPlusFee.mul(tradeFee).div(FEE_BASE.sub(tradeFee));
        amountInPlusFee = amountInPlusFee.add(tradeFeeCollected);

        // check if offer enough to cover whole input, recalculate output if not
        if (amountIn < amountInPlusFee) {
            amountInPlusFee = amountIn;
            tradeFeeCollected = amountIn.mul(tradeFee).div(FEE_BASE);
            output = amountIn.sub(tradeFeeCollected).mul(numerator);
            if (scaler > 1)
                output = (direction == scaleDirection) ? output.mul(scaler) : output.div(scaler);
            output = output.div(denominator);
        }
        price = numerator.mul(WEI).div(denominator);
    }
    function getAmountOut(address tokenIn, uint256 amountIn, address trader, bytes calldata /*data*/) external view override returns (uint256 amountOut) {
        require(amountIn > 0, 'INSUFFICIENT_INPUT_AMOUNT');
        (uint256[] memory list) = _decodeData(0x84);
        bool direction = token0 == tokenIn;
        (address oracle, uint256 tradeFee, )  = IOSWAP_RestrictedFactory(factory).checkAndGetOracleSwapParams(token0, token1);
        uint256 offerIdx;
        uint256 length = list.length;
        for (uint256 i = 0 ; i < length ; i++) {
            offerIdx = list[i];
            require(offerIdx <= counter[direction], "Offer not exist");
            require(isApprovedTrader[direction][offerIdx][trader], "Not a approved trader");
            (uint256 amountInPlusFee, uint256 offerOut,,) = _oneOutput(amountIn, trader, direction, offerIdx, oracle, tradeFee);
            amountIn = amountIn.sub(amountInPlusFee);
            amountOut = amountOut.add(offerOut);
        }
        require(amountIn == 0, "Amount exceeds available fund");
    }
    function getAmountIn(address tokenOut, uint256 amountOut, address trader, bytes calldata /*data*/) external view override returns (uint256 amountIn) {
        require(amountOut > 0, 'INSUFFICIENT_OUTPUT_AMOUNT');
        (uint256[] memory list) = _decodeData(0x84);
        bool direction = tokenOut == token1;
        (address oracle, uint256 tradeFee,)  = IOSWAP_RestrictedFactory(factory).checkAndGetOracleSwapParams(token0, token1);
        uint256 length = list.length;
        uint256 offerIdx;
        for (uint256 i  ; i < length ; i++) {
            offerIdx = list[i];
            require(offerIdx <= counter[direction], "Offer not exist");
            require(isApprovedTrader[direction][offerIdx][trader], "Not a approved trader");
            uint256 tmpInt/*=maxOut*/ = _getMaxOut(direction, offerIdx, trader);
            (tmpInt/*=offerOut*/, amountOut) = (amountOut > tmpInt) ? (tmpInt, amountOut.sub(tmpInt)) : (amountOut, 0);
            (tmpInt/*=offerIn*/,,) = _getInputFromOutput(trader, direction, oracle, offerIdx, tmpInt/*=offerOut*/);
            amountIn = amountIn.add(tmpInt/*=offerIn*/);
        }
        amountIn = amountIn.mul(FEE_BASE).div(FEE_BASE.sub(tradeFee)).add(1);
        require(amountOut == 0, "Amount exceeds available fund");
    }

    function getProviderOfferIndexLength(address provider, bool direction) external view override returns (uint256 length) {
        return providerOfferIndex[direction][provider].length;
    }
    function getTraderOffer(address trader, bool direction, uint256 start, uint256 length) external view override returns (uint256[] memory index, address[] memory provider, bool[] memory locked, uint256[] memory feePaidAndReceiving, uint256[] memory amountAndPrice, uint256[] memory startDateAndExpire) {
        return _showList(1, trader, direction, start, length);
    }  

    function getProviderOffer(address _provider, bool direction, uint256 start, uint256 length) external view override returns (uint256[] memory index, address[] memory provider, bool[] memory locked, uint256[] memory feePaidAndReceiving, uint256[] memory amountAndPrice, uint256[] memory startDateAndExpire) {
        return _showList(2, _provider, direction, start, length);
    }
    function _showList(uint256 listType, address who, bool direction, uint256 start, uint256 length) internal view returns (uint256[] memory index, address[] memory provider, bool[] memory locked, uint256[] memory feePaidAndReceiving, uint256[] memory amountAndPrice, uint256[] memory startDateAndExpire) {
        uint256 tmpInt;
        uint256[] storage __list;
        if (listType == 0) {
            __list = providerOfferIndex[direction][address(0)];
            tmpInt = offers[direction].length;
        } else if (listType == 1) {
            __list = traderOffer[direction][who];
            tmpInt = __list.length;
        } else if (listType == 2) {
            __list = providerOfferIndex[direction][who];
            tmpInt = __list.length;
        } else {
            revert("Unknown list");
        }
        uint256 _listType = listType; // stack too deep
        Offer[] storage _list = offers[direction];
        if (start < tmpInt) {
            if (start.add(length) > tmpInt) {
                length = tmpInt.sub(start);
            }
            index = new uint256[](length);
            provider = new address[](length);
            locked = new bool[](length);
            tmpInt = length * 2;
            feePaidAndReceiving = new uint256[](tmpInt);
            amountAndPrice = new uint256[](tmpInt);
            startDateAndExpire = new uint256[](tmpInt);
            for (uint256 i ; i < length ; i++) {
                tmpInt = i.add(start);
                tmpInt = _listType == 0 ? tmpInt :
                         _listType == 1 ? __list[tmpInt] :
                                         __list[tmpInt];
                Offer storage offer = _list[tmpInt];
                index[i] = tmpInt;
                tmpInt =  i.add(length);
                provider[i] = offer.provider;
                locked[i] = offer.locked;
                feePaidAndReceiving[i] = offer.feePaid;
                feePaidAndReceiving[tmpInt] = offer.receiving;
                amountAndPrice[i] = offer.amount;
                amountAndPrice[tmpInt] = offer.restrictedPrice;
                startDateAndExpire[i] = offer.startDate;
                startDateAndExpire[tmpInt] = offer.expire;
            }
        } else {
            provider = new address[](0);
            locked = new bool[](0);
            feePaidAndReceiving = amountAndPrice = startDateAndExpire = new uint256[](0);
        }
    }

    function addLiquidity(address provider, bool direction, uint256 index, uint256 feeIn, bool locked, uint256 restrictedPrice, uint256 startDate, uint256 expire) external override lock returns (uint256) {
        require(IOSWAP_RestrictedFactory(factory).isLive(), 'GLOBALLY PAUSED');
        require(msg.sender == restrictedLiquidityProvider || msg.sender == provider, "Not from router or owner");
        require(isLive, "PAUSED");
        require(provider != address(0), "Null address");
        require(expire >= startDate, "Already expired");
        require(expire >= block.timestamp, "Already expired");
        {
        uint256 maxDur = uint256(IOSWAP_ConfigStore(configStore).customParam(MAX_DUR));
        require(expire <= block.timestamp + maxDur, "Expire too far away");
        }

        (uint256 newGovBalance, uint256 newToken0Balance, uint256 newToken1Balance) = getBalances();
        require(newGovBalance.sub(lastGovBalance) >= feeIn, "Invalid feeIn");
        feeBalance = feeBalance.add(feeIn);
        uint256 amountIn;
        if (direction) {
            amountIn = newToken1Balance.sub(lastToken1Balance);
            if (govToken == token1)
                amountIn = amountIn.sub(feeIn);
        } else {
            amountIn = newToken0Balance.sub(lastToken0Balance);
            if (govToken == token0)
                amountIn = amountIn.sub(feeIn);
        }

        if (index > 0) {
            Offer storage offer = offers[direction][index];
            require(offer.provider == provider, "Not from provider");

            if (offer.restrictedPrice != restrictedPrice ||
                offer.startDate != startDate ||
                offer.expire != expire) {
                if (offer.locked) {
                    uint256 feePerOrder = uint256(IOSWAP_ConfigStore(configStore).customParam(FEE_PER_ORDER));
                    require(offer.feePaid < feePerOrder, "Order already locked");
                }
                offer.restrictedPrice = restrictedPrice;
                offer.startDate = startDate;
                offer.expire = expire;
            }
            offer.feePaid = offer.feePaid.add(feeIn);
            offer.amount = offer.amount.add(amountIn);
        } else {
            index = (++counter[direction]);
            providerOfferIndex[direction][provider].push(index);
            require(amountIn > 0, "No amount in");

            offers[direction].push(Offer({
                provider: provider,
                locked: locked,
                feePaid: feeIn,
                amount: amountIn,
                receiving: 0,
                restrictedPrice: restrictedPrice,
                startDate: startDate,
                expire: expire
            }));

            emit NewProviderOffer(provider, direction, index, locked);
        }

        lastGovBalance = newGovBalance;
        lastToken0Balance = newToken0Balance;
        lastToken1Balance = newToken1Balance;

        emit AddLiquidity(provider, direction, index, feeIn, amountIn, restrictedPrice, startDate, expire);

        return index;
    }

    function removeLiquidity(address provider, bool direction, uint256 index, uint256 amountOut, uint256 receivingOut) external override lock {
        require(msg.sender == restrictedLiquidityProvider || msg.sender == provider, "Not from router or owner");
        _removeLiquidity(provider, direction, index, amountOut, receivingOut);
        (address tokenA, address tokenB) = direction ? (token1,token0) : (token0,token1);
        _safeTransfer(tokenA, msg.sender, amountOut); // optimistically transfer tokens
        _safeTransfer(tokenB, msg.sender, receivingOut); // optimistically transfer tokens
        _sync();
    }

    function removeAllLiquidity(address provider) external override lock returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = _removeAllLiquidity1D(provider, false);
        (uint256 amount2, uint256 amount3) = _removeAllLiquidity1D(provider, true);
        amount0 = amount0.add(amount3);
        amount1 = amount1.add(amount2);
    }
    function removeAllLiquidity1D(address provider, bool direction) external override lock returns (uint256 totalAmount, uint256 totalReceiving) {
        return _removeAllLiquidity1D(provider, direction);
    }
    function _removeAllLiquidity1D(address provider, bool direction) internal returns (uint256 totalAmount, uint256 totalReceiving) {
        require(msg.sender == restrictedLiquidityProvider || msg.sender == provider, "Not from router or owner");
        uint256[] storage list = providerOfferIndex[direction][provider];
        uint256 length =  list.length;
        for (uint256 i = 0 ; i < length ; i++) {
            uint256 index = list[i];
            Offer storage offer = offers[direction][index]; 
            totalAmount = totalAmount.add(offer.amount);
            totalReceiving = totalReceiving.add(offer.receiving);
            _removeLiquidity(provider, direction, index, offer.amount, offer.receiving);
        }
        (uint256 amount0, uint256 amount1) = direction ? (totalReceiving, totalAmount) : (totalAmount, totalReceiving);
        _safeTransfer(token0, msg.sender, amount0); // optimistically transfer tokens
        _safeTransfer(token1, msg.sender, amount1); // optimistically transfer tokens
        _sync();
    }

    function _removeLiquidity(address provider, bool direction, uint256 index, uint256 amountOut, uint256 receivingOut) internal {
        require(index > 0, "Provider liquidity not found");

        Offer storage offer = offers[direction][index]; 
        require(offer.provider == provider, "Not from provider");

        if (offer.locked) {
            uint256 feePerOrder = uint256(IOSWAP_ConfigStore(configStore).customParam(FEE_PER_ORDER));
            if (offer.feePaid > feePerOrder)
                require(offer.expire < block.timestamp, "Not expired");
        }

        offer.amount = offer.amount.sub(amountOut);
        offer.receiving = offer.receiving.sub(receivingOut);

        emit RemoveLiquidity(provider, direction, index, amountOut, receivingOut);
    }

    function getApprovedTraderLength(bool direction, uint256 offerIndex) external override view returns (uint256) {
        return approvedTrader[direction][offerIndex].length;
    }
    function getApprovedTrader(bool direction, uint256 offerIndex, uint256 start, uint256 length) external view override returns (address[] memory trader, uint256[] memory allocation) {
        address[] storage list = approvedTrader[direction][offerIndex];
        uint256 listLength = list.length;
        if (start < listLength) {
            if (start.add(length) > listLength) {
                length = listLength.sub(start);
            }
            trader = new address[](length);
            allocation = new uint256[](length);
            for (uint256 i = 0 ; i < length ; i++) {
                allocation[i] = traderAllocation[direction][offerIndex][ trader[i] = list[i.add(start)] ];
            }
        } else {
            trader = new address[](0);
            allocation = new uint256[](0);
        }
    }
    function addApprovedTrader(bool direction, uint256 offerIndex, address trader, uint256 allocation) external override {
        require(msg.sender == restrictedLiquidityProvider || msg.sender == offers[direction][offerIndex].provider, "Not from router or owner");
        _addApprovedTrader(direction, offerIndex, trader, allocation);
    }
    function addMultipleApprovedTrader(bool direction, uint256 offerIndex, address[] calldata trader, uint256[] calldata allocation) external override {
        require(msg.sender == restrictedLiquidityProvider || msg.sender == offers[direction][offerIndex].provider, "Not from router or owner");
        uint256 length = trader.length;
        require(length == allocation.length, "length not match");
        for (uint256 i = 0 ; i < length ; i++) {
            _addApprovedTrader(direction, offerIndex, trader[i], allocation[i]);
        }
    }
    function _addApprovedTrader(bool direction, uint256 offerIndex, address trader, uint256 allocation) internal {
        if (!isApprovedTrader[direction][offerIndex][trader]){
            approvedTrader[direction][offerIndex].push(trader);
            isApprovedTrader[direction][offerIndex][trader] = true;
            traderOffer[direction][trader].push(offerIndex);
        }
        traderAllocation[direction][offerIndex][trader] = traderAllocation[direction][offerIndex][trader].add(allocation);

        emit ApprovedTrader(direction, offerIndex, trader, allocation);
    }

    // format for the data parameter
    // data size + offer index length + list offer index (+ amount for that offer) 
    function swap(uint256 amount0Out, uint256 amount1Out, address to, address trader, bytes calldata /*data*/) external override lock {
        if (!IOSWAP_OracleFactory(whitelistFactory).isWhitelisted(msg.sender)) {
            require(tx.origin == msg.sender && !Address.isContract(msg.sender) && trader == msg.sender, "Invalid trader");
        }

        require(isLive, "PAUSED");
        uint256 amount0In = IERC20(token0).balanceOf(address(this)).sub(lastToken0Balance);
        uint256 amount1In = IERC20(token1).balanceOf(address(this)).sub(lastToken1Balance);

        uint256 amountOut;
        uint256 protocolFeeCollected;
        if (amount0Out == 0 && amount1Out != 0){
            (amountOut, protocolFeeCollected) = _swap(true, amount0In, trader/*, data*/);
            require(amountOut >= amount1Out, "INSUFFICIENT_AMOUNT");
            _safeTransfer(token1, to, amountOut); // optimistically transfer tokens
            protocolFeeBalance0 = protocolFeeBalance0.add(protocolFeeCollected);
        } else if (amount0Out != 0 && amount1Out == 0){
            (amountOut, protocolFeeCollected) = _swap(false, amount1In, trader/*, data*/);
            require(amountOut >= amount0Out, "INSUFFICIENT_AMOUNT");
            _safeTransfer(token0, to, amountOut); // optimistically transfer tokens
            protocolFeeBalance1 = protocolFeeBalance1.add(protocolFeeCollected);
        } else {
            revert("Not supported");
        }

        _sync();
    }

    function _decodeData(uint256 offset) internal pure returns (uint256[] memory list) {
        uint256 dataRead;
        require(msg.data.length >= offset.add(0x60), "Invalid offer list");
        assembly {
            let count := calldataload(add(offset, 0x20))
            let size := mul(count, 0x20)

            if lt(calldatasize(), add(offset, add(size, 0x20))) { // offset + 0x20 + count * 0x20
                revert(0, 0)
            }
            let mark := mload(0x40)
            mstore(0x40, add(mark, add(size, 0x20))) // malloc
            mstore(mark, count) // array length
            calldatacopy(add(mark, 0x20), add(offset, 0x40), size) // copy data to list
            list := mark
            mark := add(mark, add(0x20, size))
            dataRead := add(size, 0x20)
        }
        require(offset.add(dataRead).add(0x20) == msg.data.length, "Invalid data length");
        require(list.length > 0, "Invalid offer list");
    }

    function _swap2(bool direction, address trader, uint256 offerIdx, uint256 amountIn, address oracle, uint256[4] memory fee/*uint256 tradeFee, uint256 protocolFee, uint256 feePerOrder, uint256 feePerTrander*/) internal 
        returns (uint256 remainIn, uint256 amountOut, uint256 tradeFeeCollected, uint256 protocolFeeCollected) 
    {
        require(offerIdx <= counter[direction], "Offer not exist");
        Offer storage offer = offers[direction][offerIdx];
        {
        // check approved list
        uint256 traderLen = approvedTrader[direction][offerIdx].length;
        require(
            traderLen > 0 && 
            isApprovedTrader[direction][offerIdx][trader], 
        "Not a approved trader");

        // check provider fee
        uint256 feeRequired = fee[2].add(fee[3].mul(traderLen));
        require(offer.feePaid >= feeRequired, "Insufficient fee");
        
        // check offer period
        require(block.timestamp >= offer.startDate, "Offer not begin yet");
        require(block.timestamp <= offer.expire, "Offer expired");
        }

        uint256 amountInPlusFee;
        uint256 price;
        (amountInPlusFee, amountOut, tradeFeeCollected, price) = _oneOutput(amountIn, trader, direction, offerIdx, oracle, fee[0]);

        // stack too deep, use remainIn as alloc
        remainIn = traderAllocation[direction][offerIdx][trader];
        traderAllocation[direction][offerIdx][trader] = remainIn.sub(amountOut);

        remainIn = amountIn.sub(amountInPlusFee);

        if (fee[1] != 0) {
            protocolFeeCollected = tradeFeeCollected.mul(fee[1]).div(FEE_BASE);
            amountInPlusFee/*minusProtoFee*/ = amountInPlusFee.sub(protocolFeeCollected);
        }

        offer.amount = offer.amount.sub(amountOut);
        offer.receiving = offer.receiving.add(amountInPlusFee/*minusProtoFee*/);

        emit SwappedOneOffer(offer.provider, direction, offerIdx, price, amountOut, amountInPlusFee/*minusProtoFee*/);
    }
    function _swap(bool direction, uint256 amountIn, address trader/*, bytes calldata data*/) internal returns (uint256 totalOut, uint256 totalProtocolFeeCollected) {
        (uint256[] memory list) = _decodeData(0xa4);
        uint256 remainIn = amountIn;
        address oracle;
        uint256[4] memory fee;
        (oracle, fee[0], fee[1])  = IOSWAP_RestrictedFactory(factory).checkAndGetOracleSwapParams(token0, token1);
        fee[2] = uint256(IOSWAP_ConfigStore(configStore).customParam(FEE_PER_ORDER));
        fee[3] = uint256(IOSWAP_ConfigStore(configStore).customParam(FEE_PER_TRADER));

        uint256 totalTradeFeeCollected;
        uint256 amountOut; uint256 tradeFeeCollected; uint256 protocolFeeCollected;
        for (uint256 index = 0 ; index < list.length ; index++) {
            (remainIn, amountOut, tradeFeeCollected, protocolFeeCollected) = _swap2(direction, trader, list[index], remainIn, oracle, fee);
            totalOut = totalOut.add(amountOut);
            totalTradeFeeCollected = totalTradeFeeCollected.add(tradeFeeCollected);
            totalProtocolFeeCollected = totalProtocolFeeCollected.add(protocolFeeCollected);
        }
        require(remainIn == 0, "Amount exceeds available fund");

        emit Swap(trader, direction, amountIn, totalOut, totalTradeFeeCollected, totalProtocolFeeCollected);
    }

    function sync() external override lock {
        _sync();
    }
    function _sync() internal {
        (lastGovBalance, lastToken0Balance, lastToken1Balance) = getBalances();
    }

    function redeemProtocolFee() external override lock {
        address protocolFeeTo = IOSWAP_RestrictedFactory(factory).protocolFeeTo();
        _safeTransfer(govToken, protocolFeeTo, feeBalance); // optimistically transfer tokens
        _safeTransfer(token0, protocolFeeTo, protocolFeeBalance0); // optimistically transfer tokens
        _safeTransfer(token1, protocolFeeTo, protocolFeeBalance1); // optimistically transfer tokens
        feeBalance = 0;
        protocolFeeBalance0 = 0;
        protocolFeeBalance1 = 0;
        
        _sync();
    }
}