// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.6.11;

import './interfaces/IOSWAP_VotingExecutor.sol';
import './interfaces/IOSWAP_Governance.sol';
import './interfaces/IOSWAP_Administrator.sol';

contract OSWAP_VotingExecutor is IOSWAP_VotingExecutor {

    address public governance;
    address public admin;
    
    constructor(address _governance, address _admin) public {
        governance = _governance;
        admin = _admin;
    }

    function execute(bytes32[] calldata params) external override {
        require(IOSWAP_Governance(governance).isVotingContract(msg.sender), "Not from voting");
        bytes32 name = params[0];
        bytes32 param1 = params[1];
        // most frequenly used parameter comes first
        if (params.length == 4) {
            if (name == "setVotingConfig") {
                IOSWAP_Governance(governance).setVotingConfig(param1, params[2], uint256(params[3]));
            } else {
                revert("Unknown command");
            }
        } else if (params.length == 2) {
            if (name == "setMinStakePeriod") {
                IOSWAP_Governance(governance).setMinStakePeriod(uint256(param1));
            } else if (name == "setMaxAdmin") {
                IOSWAP_Administrator(admin).setMaxAdmin(uint256(param1));
            } else if (name == "addAdmin") {
                IOSWAP_Administrator(admin).addAdmin(address(bytes20(param1)));
            } else if (name == "removeAdmin") {
                IOSWAP_Administrator(admin).removeAdmin(address(bytes20(param1)));
            } else if (name == "setAdmin") {
                IOSWAP_Governance(governance).setAdmin(address(bytes20(param1)));
            } else {
                revert("Unknown command");
            }
        } else if (params.length == 3) {
            if (name == "setVotingExecutor") {
                IOSWAP_Governance(governance).setVotingExecutor(address(bytes20(param1)), uint256(params[2])!=0);
            } else {
                revert("Unknown command");
            }
        } else if (params.length == 7) {
            if (name == "addVotingConfig") {
                IOSWAP_Governance(governance).addVotingConfig(param1, uint256(params[2]), uint256(params[3]), uint256(params[4]), uint256(params[5]), uint256(params[6]));
            } else {
                revert("Unknown command");
            }
        } else {
            revert("Invalid parameters");
        }
    }
}
