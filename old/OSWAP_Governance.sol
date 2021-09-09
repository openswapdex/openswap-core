// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './interfaces/IOSWAP_Governance.sol';
import './interfaces/IOSWAP_VotingContract.sol';
import '../interfaces/IERC20.sol';
import '../libraries/SafeMath.sol';
import '../libraries/Ownable.sol';
import '../libraries/TransferHelper.sol';

contract OSWAP_Governance is IOSWAP_Governance, Ownable {
    using SafeMath for uint256;

    modifier onlyVoting() {
        require(isVotingExecutor[msg.sender], "Not from voting");
        _; 
    }
    modifier onlyVotingRegistry() {
        require(msg.sender == votingRegister, "Not from votingRegistry");
        _; 
    }

    uint256 constant WEI = 10 ** 18;

    mapping (bytes32 => VotingConfig) public override votingConfigs;
	bytes32[] public override votingConfigProfiles;

    address public override govToken;
    mapping (address => NewStake) public override freezedStake;
    mapping (address => uint256) public override stakeOf;
    uint256 public override totalStake;

    address public override votingRegister;
    address[] public override votingExecutor;
    mapping (address => uint256) public override votingExecutorInv;
    mapping (address => bool) public override isVotingExecutor;
    address public override admin;
    uint256 public override minStakePeriod;

    uint256 public override voteCount;
    mapping (address => uint256) public override votingIdx;
    address[] public override votings;

    constructor(
        address _govToken, 
        bytes32[] memory _names,
        uint256[] memory _minExeDelay, 
        uint256[] memory _minVoteDuration, 
        uint256[] memory _maxVoteDuration, 
        uint256[] memory _minGovTokenToCreateVote, 
        uint256[] memory _minQuorum,
        uint256 _minStakePeriod
    ) public {
        govToken = _govToken;

        require(_names.length == _minExeDelay.length && 
                _minExeDelay.length == _minVoteDuration.length && 
                _minVoteDuration.length == _maxVoteDuration.length && 
                _maxVoteDuration.length == _minGovTokenToCreateVote.length && 
                _minGovTokenToCreateVote.length == _minQuorum.length, "Argument lengths not matched");
        for (uint256 i = 0 ; i < _names.length ; i++) {
            require(_minExeDelay[i] > 0 && _minExeDelay[i] <= 604800, "Invalid minExeDelay");
            require(_minVoteDuration[i] < _maxVoteDuration[i] && _minVoteDuration[i] <= 604800, "Invalid minVoteDuration");

            VotingConfig storage config = votingConfigs[_names[i]];
            config.minExeDelay = _minExeDelay[i];
            config.minVoteDuration = _minVoteDuration[i];
            config.maxVoteDuration = _maxVoteDuration[i];
            config.minGovTokenToCreateVote = _minGovTokenToCreateVote[i];
            config.minQuorum = _minQuorum[i];
			votingConfigProfiles.push(_names[i]);
            emit AddVotingConfig(_names[i], config.minExeDelay, config.minVoteDuration, config.maxVoteDuration, config.minGovTokenToCreateVote, config.minQuorum);
        }

        require(_minStakePeriod > 0 && _minStakePeriod <= 2592000, "Invalid minStakePeriod"); // max 30 days
        minStakePeriod = _minStakePeriod;

        emit ParamSet("minStakePeriod", bytes32(minStakePeriod));
    }


	function votingConfigProfilesLength() external view override returns(uint256) {
		return votingConfigProfiles.length;
	}
	function getVotingConfigProfiles(uint256 start, uint256 length) external view override returns(bytes32[] memory profiles) {
		if (start < votingConfigProfiles.length) {
            if (start.add(length) > votingConfigProfiles.length)
                length = votingConfigProfiles.length.sub(start);
            profiles = new bytes32[](length);
            for (uint256 i = 0 ; i < length ; i++) {
                profiles[i] = votingConfigProfiles[i.add(start)];
            }
        }
	}
    function getVotingParams(bytes32 name) external view override returns (uint256 _minExeDelay, uint256 _minVoteDuration, uint256 _maxVoteDuration, uint256 _minGovTokenToCreateVote, uint256 _minQuorum) {
        VotingConfig storage config = votingConfigs[name];
        if (config.minGovTokenToCreateVote == 0){
            config = votingConfigs["vote"];
        }
        return (config.minExeDelay, config.minVoteDuration, config.maxVoteDuration, config.minGovTokenToCreateVote, config.minQuorum);
    }

    function setVotingRegister(address _votingRegister) external override onlyOwner {
        require(votingRegister == address(0), "Already set");
        votingRegister = _votingRegister;
        emit ParamSet("votingRegister", bytes32(bytes20(votingRegister)));
    }    
    function votingExecutorLength() external view override returns (uint256) {
        return votingExecutor.length;
    }
    function initVotingExecutor(address[] calldata  _votingExecutor) external override onlyOwner {
        require(votingExecutor.length == 0, "executor already set");
        uint256 length = _votingExecutor.length;
        for (uint256 i = 0 ; i < length ; i++) {
            _setVotingExecutor(_votingExecutor[i], true);
        }
    }
    function setVotingExecutor(address _votingExecutor, bool _bool) external override onlyVoting {
        _setVotingExecutor(_votingExecutor, _bool);
    }
    function _setVotingExecutor(address _votingExecutor, bool _bool) internal {
        require(_votingExecutor != address(0), "Invalid executor");
        
        if (votingExecutor.length==0 || votingExecutor[votingExecutorInv[_votingExecutor]] != _votingExecutor) {
            votingExecutorInv[_votingExecutor] = votingExecutor.length; 
            votingExecutor.push(_votingExecutor);
        } else {
            require(votingExecutorInv[_votingExecutor] != 0, "cannot reset main executor");
        }
        isVotingExecutor[_votingExecutor] = _bool;
        emit ParamSet2("votingExecutor", bytes32(bytes20(_votingExecutor)), bytes32(uint256(_bool ? 1 : 0)));
    }
    function initAdmin(address _admin) external override onlyOwner {
        require(admin == address(0), "Already set");
        _setAdmin(_admin);
    }
    function setAdmin(address _admin) external override onlyVoting {
        _setAdmin(_admin);
    }
    function _setAdmin(address _admin) internal {
        require(_admin != address(0), "Invalid admin");
        admin = _admin;
        emit ParamSet("admin", bytes32(bytes20(admin)));
    }
    function addVotingConfig(bytes32 name, uint256 minExeDelay, uint256 minVoteDuration, uint256 maxVoteDuration, uint256 minGovTokenToCreateVote, uint256 minQuorum) external override onlyVoting {
        require(minExeDelay > 0 && minExeDelay <= 604800, "Invalid minExeDelay");
        require(minVoteDuration < maxVoteDuration && minVoteDuration <= 604800, "Invalid voteDuration");
        require(minGovTokenToCreateVote <= totalStake, "Invalid minGovTokenToCreateVote");
        require(minQuorum <= totalStake, "Invalid minQuorum");

        VotingConfig storage config = votingConfigs[name];
        require(config.minExeDelay == 0, "Config already exists");

        config.minExeDelay = minExeDelay;
        config.minVoteDuration = minVoteDuration;
        config.maxVoteDuration = maxVoteDuration;
        config.minGovTokenToCreateVote = minGovTokenToCreateVote;
        config.minQuorum = minQuorum;
		votingConfigProfiles.push(name);
        emit AddVotingConfig(name, minExeDelay, minVoteDuration, maxVoteDuration, minGovTokenToCreateVote, minQuorum);
    }
    function setVotingConfig(bytes32 configName, bytes32 paramName, uint256 paramValue) external override onlyVoting {
        require(votingConfigs[configName].minExeDelay > 0, "Config not exists");
        if (paramName == "minExeDelay") {
            require(paramValue > 0 && paramValue <= 604800, "Invalid minExeDelay");
            votingConfigs[configName].minExeDelay = paramValue;
        } else if (paramName == "minVoteDuration") {
            require(paramValue < votingConfigs[configName].maxVoteDuration && paramValue <= 604800, "Invalid voteDuration");
            votingConfigs[configName].minVoteDuration = paramValue;
        } else if (paramName == "maxVoteDuration") {
            require(votingConfigs[configName].minVoteDuration < paramValue, "Invalid voteDuration");
            votingConfigs[configName].maxVoteDuration = paramValue;
        } else if (paramName == "minGovTokenToCreateVote") {
            require(paramValue <= totalStake, "Invalid minGovTokenToCreateVote");
            votingConfigs[configName].minGovTokenToCreateVote = paramValue;
        } else if (paramName == "minQuorum") {
            require(paramValue <= totalStake, "Invalid minQuorum");
            votingConfigs[configName].minQuorum = paramValue;
        }
        emit SetVotingConfig(configName, paramName, paramValue);
    }
    function setMinStakePeriod(uint _minStakePeriod) external override onlyVoting {
        require(_minStakePeriod > 0 && _minStakePeriod <= 2592000, "Invalid minStakePeriod"); // max 30 days
        minStakePeriod = _minStakePeriod;
        emit ParamSet("minStakePeriod", bytes32(minStakePeriod));
    }

    function stake(uint256 value) external override {
        require(value <= IERC20(govToken).balanceOf(msg.sender), "insufficient balance");
        TransferHelper.safeTransferFrom(govToken, msg.sender, address(this), value);

        NewStake storage newStake = freezedStake[msg.sender];
        newStake.amount = newStake.amount.add(value);
        newStake.timestamp = block.timestamp;
    }
    function unlockStake() external override {
        NewStake storage newStake = freezedStake[msg.sender];
        require(newStake.amount > 0, "Nothing to stake");
        require(newStake.timestamp.add(minStakePeriod) < block.timestamp, "Freezed period not passed");
        uint256 value = newStake.amount;
        delete freezedStake[msg.sender];
        _stake(value);
    }
    function _stake(uint256 value) private {
        stakeOf[msg.sender] = stakeOf[msg.sender].add(value);
        totalStake = totalStake.add(value);
        updateWeight(msg.sender);
        emit Stake(msg.sender, value);
    }
    function unstake(uint256 value) external override {
        require(value <= stakeOf[msg.sender].add(freezedStake[msg.sender].amount), "unlock value exceed locked fund");
        if (value <= freezedStake[msg.sender].amount){
            freezedStake[msg.sender].amount = freezedStake[msg.sender].amount.sub(value);
        } else {
            uint256 value2 = value.sub(freezedStake[msg.sender].amount);
            delete freezedStake[msg.sender];
            stakeOf[msg.sender] = stakeOf[msg.sender].sub(value2);
            totalStake = totalStake.sub(value2);
            updateWeight(msg.sender);
            emit Unstake(msg.sender, value2);
        }
        TransferHelper.safeTransfer(govToken, msg.sender, value);
    }

    function allVotings() external view override returns (address[] memory) {
        return votings;
    }
    function getVotingCount() external view override returns (uint256) {
        return votings.length;
    }
    function getVotings(uint256 start, uint256 count) external view override returns (address[] memory _votings) {
        if (start.add(count) > votings.length) {
            count = votings.length - start;
        }
        _votings = new address[](count);
        uint256 j = start;
        for (uint256 i = 0; i < count ; i++) {
            _votings[i] = votings[j];
            j++;
        }
    }

    function isVotingContract(address votingContract) external view override returns (bool) {
        return votings[votingIdx[votingContract]] == votingContract;
    }

    function getNewVoteId() external override onlyVotingRegistry returns (uint256) {
        voteCount++;
        return voteCount;
    }

    function newVote(address vote, bool isExecutiveVote) external override onlyVotingRegistry {
        require(vote != address(0), "Invalid voting address");
        require(votings.length == 0 || votings[votingIdx[vote]] != vote, "Voting contract already exists");

        // close expired poll
        uint256 i = 0;
        while (i < votings.length) {
            IOSWAP_VotingContract voting = IOSWAP_VotingContract(votings[i]);
            if (voting.executeParam().length == 0 && voting.voteEndTime() < block.timestamp) {
                _closeVote(votings[i]);
            } else {
                i++;
            }
        }

        votingIdx[vote] = votings.length;
        votings.push(vote);
        if (isExecutiveVote){
            emit NewVote(vote);
        } else {
            emit NewPoll(vote);
        }
    }

    function voted(bool poll, address account, uint256 option) external override {
        require(votings[votingIdx[msg.sender]] == msg.sender, "Voting contract not exists");
        if (poll)
            emit Poll(account, msg.sender, option);
        else
            emit Vote(account, msg.sender, option);
    }

    function updateWeight(address account) private {
        for (uint256 i = 0; i < votings.length; i ++){
            IOSWAP_VotingContract(votings[i]).updateWeight(account);
        }
    }

    function executed() external override {
        require(votings[votingIdx[msg.sender]] == msg.sender, "Voting contract not exists");
        _closeVote(msg.sender);
        emit Executed(msg.sender);
    }

    function veto(address voting) external override {
        require(msg.sender == admin, "Not from shutdown admin");
        IOSWAP_VotingContract(voting).veto();
        _closeVote(voting);
        emit Veto(voting);
    }

    function closeVote(address vote) external override {
        require(IOSWAP_VotingContract(vote).executeParam().length == 0, "Not a Poll");
        require(block.timestamp > IOSWAP_VotingContract(vote).voteEndTime(), "Voting not ended");
        _closeVote(vote);
    }
    function _closeVote(address vote) internal {
        uint256 idx = votingIdx[vote];
        require(idx > 0 || votings[0] == vote, "Voting contract not exists");
        if (idx < votings.length - 1) {
            votings[idx] = votings[votings.length - 1];
            votingIdx[votings[idx]] = idx;
        }
        votingIdx[vote] = 0;
        votings.pop();
    }
}