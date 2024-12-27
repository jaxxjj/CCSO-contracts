// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../verifier/CrossChainStateVerifier.sol";

interface ICCTOServiceManager {
    // Custom errors
    error CCTOServiceManager__TaskAlreadyResponded();
    error CCTOServiceManager__TaskHashMismatch();
    error CCTOServiceManager__InvalidSignature();
    error CCTOServiceManager__TaskNotFound();
    error CCTOServiceManager__InvalidChallenge();
    error CCTOServiceManager__ChallengePeriodActive();
    error CCTOServiceManager__InsufficientChallengeBond();

    // Events
    event TaskResponded(uint32 indexed taskIndex, Task task, address indexed operator);
    event TaskChallenged(uint256 indexed chainId, uint256 blockNumber, bytes32 claimedState, address indexed operator);
    
    // Task struct
    struct Task {
        uint256 chainId;
        uint256 blockNumber;
        bytes32 stateValue;
        uint32 taskCreatedBlock;
    }

    // Core functions
    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external;

    function submitStateChallenge(
        uint256 chainId,
        uint256 blockNumber,
        bytes32 claimedState,
        bytes memory proof,
        address operator
    ) external payable;

    // View functions
    function getTaskResponse(address operator, uint32 taskNum) external view returns (bytes32);
    function getTaskHash(uint32 taskNum) external view returns (bytes32);
    function latestTaskNum() external view returns (uint32);
}
