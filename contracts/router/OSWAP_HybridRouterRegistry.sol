// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import "./interfaces/IOSWAP_HybridRouterRegistry.sol";
import '../libraries/Ownable.sol';
import '../gov/interfaces/IOSWAP_Governance.sol';

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
}
interface IFactoryV3 {
    function getPair(address tokenA, address tokenB, uint256 index) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
}

interface IPair {
    function token0() external returns (address);
    function token1() external returns (address);
}

contract OSWAP_HybridRouterRegistry is Ownable, IOSWAP_HybridRouterRegistry {

    modifier onlyVoting() {
        require(IOSWAP_Governance(governance).isVotingExecutor(msg.sender), "Not from voting");
        _; 
    }

    mapping (address => Pair) public override pairs;
    mapping (address => Protocol) public override protocols;
    address[] public override protocolList;

    address public override governance;

    constructor(address _governance) public {
        governance = _governance;
    }

    function protocolListLength() public override view returns (uint256) {
        return protocolList.length;
    }

    function init(bytes32[] calldata _name, address[] calldata _factory, uint256[] calldata _fee, uint256[] calldata _feeBase, uint256[] calldata _typeCode) external onlyOwner {
        require(protocolList.length == 0 , "Already init");
        uint256 length = _name.length;
        require(length == _factory.length && _factory.length == _fee.length && _fee.length == _typeCode.length, "length not match");
        for (uint256 i = 0 ; i < length ; i++) {
            _registerProtocol(_name[i], _factory[i], _fee[i], _feeBase[i], _typeCode[i]);
        }
    }
    function registerProtocol(bytes32 _name, address _factory, uint256 _fee, uint256 _feeBase, uint256 _typeCode) external override onlyVoting {
        _registerProtocol(_name, _factory, _fee, _feeBase, _typeCode);
    }
    function _registerProtocol(bytes32 _name, address _factory, uint256 _fee, uint256 _feeBase, uint256 _typeCode) internal {
        require(_factory > address(0), "Invalid protocol address");
        require(_fee <= _feeBase, "Fee too large");
        require(_feeBase > 0, "Protocol not regconized");
        protocols[_factory] = Protocol({
            name: _name,
            fee: _fee,
            feeBase: _feeBase,
            typeCode: _typeCode
        });
        protocolList.push(_factory);
        emit ProtocolRegister(_factory, _name, _fee, _feeBase, _typeCode);
    }

    // register individual pair
    function registerPair(address pairAddress, uint256 fee, uint256 feeBase) external override onlyVoting {
        require(pairAddress > address(0), "Invalid pair address");
        require(fee <= feeBase, "Fee too large");
        require(feeBase > 0, "Protocol not regconized");
        _registerPair(address(0), pairAddress, fee, feeBase);
    }
    function registerPair(address token0, address token1, address pairAddress, uint256 fee, uint256 feeBase) external override onlyVoting {
        require(token0 > address(0), "Invalid token address");
        require(token0 < token1, "Invalid token order");
        require(pairAddress > address(0), "Invalid pair address");
        require(fee <= feeBase, "Fee too large");
        require(feeBase > 0, "Protocol not regconized");

        pairs[pairAddress].token0 = token0;
        pairs[pairAddress].token1 = token1;
        pairs[pairAddress].fee = fee;
        pairs[pairAddress].feeBase = feeBase;
        emit PairRegister(address(0), pairAddress, token0, token1);
    }


    // register pair with registered protocol
    function registerPairByIndex(address _factory, uint256 index) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        address pairAddress = IFactory(_factory).allPairs(index);
        _registerPair(_factory, pairAddress, fee, feeBase);
    }
    function registerPairsByIndex(address _factory, uint256[] calldata index) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        uint256 length = index.length;
        for (uint256 i = 0 ; i < length ; i++) {
            address pairAddress = IFactory(_factory).allPairs(index[i]);
            _registerPair(_factory, pairAddress, fee, feeBase);
        }
    }
    function registerPairByTokens(address _factory, address _token0, address _token1) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        require(protocols[_factory].typeCode < 3, "Invalid type");
        address pairAddress = IFactory(_factory).getPair(_token0, _token1);
        _registerPair(_factory, pairAddress, fee, feeBase);
    }

    function registerPairByTokensV3(address _factory, address _token0, address _token1, uint256 pairIndex) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        require(protocols[_factory].typeCode == 3, "Invalid type");
        address pairAddress = IFactoryV3(_factory).getPair(_token0, _token1, pairIndex);
        _registerPair(_factory, pairAddress, fee, feeBase);
    }
    function registerPairsByTokens(address _factory, address[] calldata _token0, address[] calldata _token1) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        require(protocols[_factory].typeCode < 3, "Invalid type");
        uint256 length = _token0.length;
        require(length == _token1.length, "array length not match");
        for (uint256 i = 0 ; i < length ; i++) {
            address pairAddress = IFactory(_factory).getPair(_token0[i], _token1[i]);
            _registerPair(_factory, pairAddress, fee, feeBase);
        }
    }
    function registerPairsByTokensV3(address _factory, address[] calldata _token0, address[] calldata _token1, uint256[] calldata _pairIndex) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        require(protocols[_factory].typeCode == 3, "Invalid type");
        uint256 length = _token0.length;
        require(length == _token1.length, "array length not match");
        for (uint256 i = 0 ; i < length ; i++) {
            address pairAddress = IFactoryV3(_factory).getPair(_token0[i], _token1[i], _pairIndex[i]);
            _registerPair(_factory, pairAddress, fee, feeBase);
        }
    }
    function registerPairByAddress(address _factory, address pairAddress) external override {
        uint256 fee = protocols[_factory].fee;
        uint256 feeBase = protocols[_factory].feeBase;
        require(feeBase > 0, "Protocol not regconized");
        _registerPair(_factory, pairAddress, fee, feeBase);
    }

    function _registerPair(address _factory, address pairAddress, uint256 fee, uint256 feeBase) internal {
        require(pairAddress > address(0), "Invalid pair address/Pair not found");
        address token0 = IPair(pairAddress).token0();
        address token1 = IPair(pairAddress).token1();
        require(token0 < token1, "Invalid tokens order");
        pairs[pairAddress].factory = _factory;
        pairs[pairAddress].token0 = token0;
        pairs[pairAddress].token1 = token1;
        pairs[pairAddress].fee = fee;
        pairs[pairAddress].feeBase = feeBase;
        emit PairRegister(_factory, pairAddress, token0, token1);
    }

    function getPairTokens(address[] calldata pairAddress) external override view returns (address[] memory token0, address[] memory token1) {
        uint256 length = pairAddress.length;
        token0 = new address[](length);
        token1 = new address[](length);
        for (uint256 i = 0 ; i < length ; i++) {
            Pair storage pair = pairs[pairAddress[i]];
            token0[i] = pair.token0;
            token1[i] = pair.token1;
        }
    }
    function getProtocolByPair(address pairAddress) external override view returns (
        bytes32 name,
        uint256 fee,
        uint256 feeBase,
        uint256 typeCode
    ) {
        Protocol storage protocol = protocols[pairs[pairAddress].factory];
        return (protocol.name, protocol.fee, protocol.feeBase, protocol.typeCode);
    }
}