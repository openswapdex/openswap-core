// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './interfaces/IOSWAP_Governance.sol';
import './interfaces/IOSWAP_VotingContract.sol';
import '../libraries/SafeMath.sol';

interface IOSWAP_VotingExecutor {
    function execute(bytes32[] calldata params) external;
}

contract OSWAP_VotingContract is IOSWAP_VotingContract {
    using SafeMath for uint256;

    uint256 constant WEI = 10 ** 18;
    
    address public override governance;
    address public override executor;

    uint256 public override id;
    bytes32 public override name;
    bytes32[] public override _options;
    uint256 public override quorum;
    uint256 public override threshold;
    
    uint256 public override voteStartTime;
    uint256 public override voteEndTime;
    uint256 public override executeDelay;
    bool public override executed;
    bool public override vetoed;
    

    mapping (address => uint256) public override accountVoteOption;
    mapping (address => uint256) public override accountVoteWeight;
    uint256[] public override  _optionsWeight;
    uint256 public override totalVoteWeight;
    uint256 public override totalWeight;
    bytes32[] public override _executeParam;

    constructor(address governance_, 
                address executor_, 
                uint256 id_, 
                bytes32 name_, 
                bytes32[] memory options_, 
                uint256 quorum_, 
                uint256 threshold_, 
                uint256 voteEndTime_,
                uint256 executeDelay_, 
                bytes32[] memory executeParam_
               ) public {
        require(block.timestamp <= voteEndTime_, 'Voting already ended');
        if (executeParam_.length != 0){
            require(IOSWAP_Governance(governance_).isVotingExecutor(executor_), "Invalid executor");
            require(options_.length == 2 && options_[0] == 'Y' && options_[1] == 'N', "Invalid options");
            require(threshold_ <= WEI, "Invalid threshold");
            require(executeDelay_ > 0, "Invalid execute delay");
        }
        governance = governance_;
        executor = executor_;
        totalWeight = IOSWAP_Governance(governance).totalStake();
        id = id_;
        name = name_;
        _options = options_;
        quorum = quorum_;
        threshold = threshold_;
        _optionsWeight = new uint256[](options_.length);
        
        voteStartTime = block.timestamp;
        voteEndTime = voteEndTime_;
        executeDelay = executeDelay_;
        _executeParam = executeParam_;
    }
    function getParams() external view override returns (
        address executor_,
        uint256 id_,
        bytes32 name_,
        bytes32[] memory options_,
        uint256 voteStartTime_,
        uint256 voteEndTime_,
        uint256 executeDelay_,
        bool[2] memory status_, // [executed, vetoed]
        uint256[] memory optionsWeight_,
        uint256[3] memory quorum_, // [quorum, threshold, totalWeight]
        bytes32[] memory executeParam_
    ) {
        return (executor, id, name, _options, voteStartTime, voteEndTime, executeDelay, [executed, vetoed], _optionsWeight, [quorum, threshold, totalWeight], _executeParam);
    }
    function veto() external override {
        require(msg.sender == governance, 'Not from Governance');
        require(!executed, 'Already executed');
        vetoed = true;
    }
    function optionsCount() external view override returns(uint256){
        return _options.length;
    }
    function options() external view override returns (bytes32[] memory){
        return _options;
    }
    function optionsWeight() external view override returns (uint256[] memory){
        return _optionsWeight;
    }
    function execute() external override {
        require(block.timestamp > voteEndTime.add(executeDelay), "Execute delay not past yet");
        require(!vetoed, 'Vote already vetoed');
        require(!executed, 'Vote already executed');
        require(_executeParam.length != 0, 'Execute param not defined');

        require(totalVoteWeight >= quorum, 'Quorum not met');
        require(_optionsWeight[0] > _optionsWeight[1], "Majority not met"); // 0: Y, 1:N
        require(_optionsWeight[0].mul(WEI) > totalVoteWeight.mul(threshold), "Threshold not met");
        executed = true;
        IOSWAP_VotingExecutor(executor).execute(_executeParam);
        IOSWAP_Governance(governance).executed();
    }
    function vote(uint256 option) external override {
        require(block.timestamp <= voteEndTime, 'Vote already ended');
        require(!vetoed, 'Vote already vetoed');
        require(!executed, 'Vote already executed');
        require(option < _options.length, 'Invalid option');

        IOSWAP_Governance(governance).voted(_executeParam.length == 0, msg.sender, option);

        uint256 currVoteWeight = accountVoteWeight[msg.sender];
        if (currVoteWeight > 0){
            uint256 currVoteIdx = accountVoteOption[msg.sender];    
            _optionsWeight[currVoteIdx] = _optionsWeight[currVoteIdx].sub(currVoteWeight);
            totalVoteWeight = totalVoteWeight.sub(currVoteWeight);
        }
        
        uint256 weight = IOSWAP_Governance(governance).stakeOf(msg.sender);
        require(weight > 0, "Not staked to vote");
        accountVoteOption[msg.sender] = option;
        accountVoteWeight[msg.sender] = weight;
        _optionsWeight[option] = _optionsWeight[option].add(weight);
        totalVoteWeight = totalVoteWeight.add(weight);

        totalWeight = IOSWAP_Governance(governance).totalStake();
    }
    function updateWeight(address account) external override {
        // use if-cause and don't use requrie() here to avoid revert as Governance is looping through all votings
        if (block.timestamp <= voteEndTime && !vetoed && !executed){
            uint256 weight = IOSWAP_Governance(governance).stakeOf(account);
            uint256 currVoteWeight = accountVoteWeight[account];
            if (currVoteWeight > 0 && currVoteWeight != weight){
                uint256 currVoteIdx = accountVoteOption[account];
                accountVoteWeight[account] = weight;
                _optionsWeight[currVoteIdx] = _optionsWeight[currVoteIdx].sub(currVoteWeight).add(weight);
                totalVoteWeight = totalVoteWeight.sub(currVoteWeight).add(weight);
            }
            totalWeight = IOSWAP_Governance(governance).totalStake();
        }
    }
    function executeParam() external view override returns (bytes32[] memory){
        return _executeParam;
    }
}