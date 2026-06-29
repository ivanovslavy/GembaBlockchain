// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Mini on-chain governance lifecycle: propose -> vote -> queue -> execute, against a test
// target. Proposals are keyed by a harness-chosen unique id (deterministic). Each tx is valid
// for its phase; the harness drives the time windows (1-address-1-vote, quorum 1) so nothing
// reverts.
contract GovTarget {
    uint256 public executed;
    event Executed(uint256 total);
    function doThing() external { executed += 1; emit Executed(executed); }
}

contract MiniGov {
    uint256 public constant VOTING_PERIOD = 40;  // seconds
    uint256 public constant TIMELOCK = 40;        // seconds
    uint256 public constant QUORUM = 1;

    mapping(uint256 => bool) public exists;
    mapping(uint256 => uint256) public createdAt;
    mapping(uint256 => address) public targetOf;
    mapping(uint256 => uint256) public forVotes;
    mapping(uint256 => bool) public queued;
    mapping(uint256 => uint256) public queuedAt;
    mapping(uint256 => bool) public executed;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event Proposed(uint256 indexed pid, address indexed by, address target);
    event Voted(uint256 indexed pid, address indexed voter, uint256 forVotes);
    event Queued(uint256 indexed pid);
    event ExecutedProp(uint256 indexed pid);

    function propose(uint256 pid, address target) external {
        require(!exists[pid], "exists");
        require(target != address(0), "target");
        exists[pid] = true; createdAt[pid] = block.timestamp; targetOf[pid] = target;
        emit Proposed(pid, msg.sender, target);
    }
    function vote(uint256 pid) external {
        require(exists[pid], "no prop");
        require(block.timestamp <= createdAt[pid] + VOTING_PERIOD, "closed");
        require(!hasVoted[pid][msg.sender], "voted");
        hasVoted[pid][msg.sender] = true; forVotes[pid] += 1;
        emit Voted(pid, msg.sender, forVotes[pid]);
    }
    function queue(uint256 pid) external {
        require(exists[pid] && !queued[pid], "queued");
        require(block.timestamp > createdAt[pid] + VOTING_PERIOD, "voting open");
        require(forVotes[pid] >= QUORUM, "quorum");
        queued[pid] = true; queuedAt[pid] = block.timestamp;
        emit Queued(pid);
    }
    function execute(uint256 pid) external {
        require(queued[pid] && !executed[pid], "exec");
        require(block.timestamp > queuedAt[pid] + TIMELOCK, "timelock");
        executed[pid] = true; // effects before interaction
        (bool ok, ) = targetOf[pid].call(abi.encodeWithSignature("doThing()"));
        require(ok, "call");
        emit ExecutedProp(pid);
    }
}
