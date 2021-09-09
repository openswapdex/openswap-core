// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import "./interfaces/IOSWAP_Administrator.sol";
import "./interfaces/IOSWAP_Governance.sol";
import "../commons/interfaces/IOSWAP_PausableFactory.sol";
import '../libraries/SafeMath.sol';

contract OSWAP_Administrator is IOSWAP_Administrator {
    using SafeMath for uint256;

    modifier onlyVoting() {
        require(IOSWAP_Governance(governance).isVotingExecutor(msg.sender), "Not from voting");
        _; 
    }
    modifier onlyShutdownAdmin() {
        require(admins[adminsIdx[msg.sender]] == msg.sender, "Not a shutdown admin");
        _; 
    }

    address public override immutable governance;

    uint256 public override maxAdmin;
    address[] public override admins;
    mapping (address => uint256) public override adminsIdx;

    mapping (address => mapping (address => bool)) public override vetoVotingVote;
    mapping (address => mapping (address => bool)) public override factoryShutdownVote;
    mapping (address => mapping (address => bool)) public override factoryRestartVote;
    mapping (address => mapping (address => bool)) public override pairShutdownVote;
    mapping (address => mapping (address => bool)) public override pairRestartVote;
    
    constructor(address _governance) public {
        governance = _governance;
    }

    function allAdmins() external override view returns (address[] memory) {
        return admins;
    }

    function setMaxAdmin(uint256 _maxAdmin) external override onlyVoting {
        maxAdmin = _maxAdmin;
        emit SetMaxAdmin(maxAdmin);
    }
    function addAdmin(address _admin) external override onlyVoting {
        require(admins.length.add(1) <= maxAdmin, "Max shutdown admin reached");
        require(_admin != address(0), "INVALID_SHUTDOWN_ADMIN");
        require(admins.length == 0 || admins[adminsIdx[_admin]] != _admin, "already a shutdown admin");
         adminsIdx[_admin] = admins.length;
        admins.push(_admin);
        emit AddAdmin(_admin);
    }
    function removeAdmin(address _admin) external override onlyVoting {
        uint256 idx = adminsIdx[_admin];
        require(idx > 0 || admins[0] == _admin, "Shutdown admin not exists");

        if (idx < admins.length - 1) {
            admins[idx] = admins[admins.length - 1];
            adminsIdx[admins[idx]] = idx;
        }
        adminsIdx[_admin] = 0;
        admins.pop();
        emit RemoveAdmin(_admin);
    }

    function getVote(mapping (address => bool) storage map) private view returns (bool[] memory votes) {
        uint length = admins.length;
        votes = new bool[](length);
        for (uint256 i = 0 ; i < length ; i++) {
            votes[i] = map[admins[i]];
        }
    }
    function checkVote(mapping (address => bool) storage map) private view returns (bool){
        uint256 count = 0;
        uint length = admins.length;
        uint256 quorum = length >> 1;
        for (uint256 i = 0 ; i < length ; i++) {
            if (map[admins[i]]) {
                count++;
                if (count > quorum) {
                    return true;
                }
            }
        }
        return false;
    }
    function clearVote(mapping (address => bool) storage map) private {
        uint length = admins.length;
        for (uint256 i = 0 ; i < length ; i++) {
            map[admins[i]] = false;
        }
    }

    function vetoVoting(address votingContract, bool YorN) external override onlyShutdownAdmin {
        vetoVotingVote[votingContract][msg.sender] = YorN;
        emit VotedVeto(msg.sender, votingContract, YorN);
    }
    function getVetoVotingVote(address votingContract) external override view returns (bool[] memory votes) {
        return getVote(vetoVotingVote[votingContract]);
    }
    function executeVetoVoting(address votingContract) external override {
        require(checkVote(vetoVotingVote[votingContract]), "Quorum not met");
        IOSWAP_Governance(governance).veto(votingContract);
        clearVote(vetoVotingVote[votingContract]);
    }

    function factoryShutdown(address factory, bool YorN) external override onlyShutdownAdmin {
        factoryShutdownVote[factory][msg.sender] = YorN;
        emit VotedFactoryShutdown(msg.sender, factory, YorN);
    }
    function getFactoryShutdownVote(address factory) external override view returns (bool[] memory votes) {
        return getVote(factoryShutdownVote[factory]);
    }
    function executeFactoryShutdown(address factory) external override {
        require(checkVote(factoryShutdownVote[factory]), "Quorum not met");
        IOSWAP_PausableFactory(factory).setLive(false);
        clearVote(factoryShutdownVote[factory]);
    }

    function factoryRestart(address factory, bool YorN) external override onlyShutdownAdmin {
        factoryRestartVote[factory][msg.sender] = YorN;
        emit VotedFactoryRestart(msg.sender, factory, YorN);
    }
    function getFactoryRestartVote(address factory) external override view returns (bool[] memory votes) {
        return getVote(factoryRestartVote[factory]);
    }
    function executeFactoryRestart(address factory) external override {
        require(checkVote(factoryRestartVote[factory]), "Quorum not met");
        IOSWAP_PausableFactory(factory).setLive(true);
        clearVote(factoryRestartVote[factory]);
    }

    function pairShutdown(address pair, bool YorN) external override onlyShutdownAdmin {
        pairShutdownVote[pair][msg.sender] = YorN;
        emit VotedPairShutdown(msg.sender, pair, YorN);
    }
    function getPairShutdownVote(address pair) external override view returns (bool[] memory votes) {
        return getVote(pairShutdownVote[pair]);
    }
    function executePairShutdown(address factory, address pair) external override {
        require(checkVote(pairShutdownVote[pair]), "Quorum not met");
        IOSWAP_PausableFactory(factory).setLiveForPair(pair, false);
        clearVote(pairShutdownVote[pair]);
    }

    function pairRestart(address pair, bool YorN) external override onlyShutdownAdmin {
        pairRestartVote[pair][msg.sender] = YorN;
        emit VotedPairRestart(msg.sender, pair, YorN);
    }
    function getPairRestartVote(address pair) external override view returns (bool[] memory votes) {
        return getVote(pairRestartVote[pair]);
    }
    function executePairRestart(address factory, address pair) external override {
        require(checkVote(pairRestartVote[pair]), "Quorum not met");
        IOSWAP_PausableFactory(factory).setLiveForPair(pair, true);
        clearVote(pairRestartVote[pair]);
    }
}