// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import "./interfaces/IOSWAP_VotingRegistry.sol";
import "./OSWAP_VotingContract.sol";
import '../libraries/SafeMath.sol';

contract OSWAP_VotingRegistry is IOSWAP_VotingRegistry {
    using SafeMath for uint256;

    address public override governance;

    constructor(address _governance) public {
        governance = _governance;
    }

    function newVote(address executor,
                     bytes32 name, 
                     bytes32[] calldata options, 
                     uint256 quorum, 
                     uint256 threshold, 
                     uint256 voteEndTime,
                     uint256 executeDelay, 
                     bytes32[] calldata executeParam
    ) external override {
        bool isExecutiveVote = executeParam.length != 0;
        {
        require(IOSWAP_Governance(governance).isVotingExecutor(executor), "Invalid executor");
        bytes32 configName = isExecutiveVote ? executeParam[0] : bytes32("poll");
        (uint256 minExeDelay, uint256 minVoteDuration, uint256 maxVoteDuration, uint256 minGovTokenToCreateVote, uint256 minQuorum) = IOSWAP_Governance(governance).getVotingParams(configName);
        uint256 staked = IOSWAP_Governance(governance).stakeOf(msg.sender);
        require(staked >= minGovTokenToCreateVote, "minGovTokenToCreateVote not met");
        require(voteEndTime.sub(block.timestamp) >= minVoteDuration, "minVoteDuration not met");
        require(voteEndTime.sub(block.timestamp) <= maxVoteDuration, "exceeded maxVoteDuration");
        if (isExecutiveVote) {
            require(quorum >= minQuorum, "minQuorum not met");
            require(executeDelay >= minExeDelay, "minExeDelay not met");
        }
        }

        uint256 id = IOSWAP_Governance(governance).getNewVoteId();
        OSWAP_VotingContract voting = new OSWAP_VotingContract(governance, executor, id, name, options, quorum, threshold, voteEndTime, executeDelay, executeParam);
        IOSWAP_Governance(governance).newVote(address(voting), isExecutiveVote);
    }
}