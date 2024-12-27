// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@eigenlayer-middleware/src/libraries/BN254.sol";
import "../state-manager/IStateManager.sol";
import {IBLSSignatureChecker} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";

/// @title ICCTOTaskManager
/// @notice interface for cross chain task oracle task management
interface ICCTOTaskManager {
    // custom errors
    error CCTOTaskManager__OnlyAggregator();
    error CCTOTaskManager__OnlyOwner();
    error CCTOTaskManager__TaskAlreadyResponded();
    error CCTOTaskManager__TaskResponseTooLate();
    error CCTOTaskManager__TaskHashMismatch();
    error CCTOTaskManager__QuorumThresholdNotMet();
    error CCTOTaskManager__TaskNotResponded();
    error CCTOTaskManager__TaskResponseMismatch();
    error CCTOTaskManager__TaskAlreadyChallenged();
    error CCTOTaskManager__ChallengePeriodExpired();

    // events
    event TaskResponded(TaskResponse taskResponse, TaskResponseMetadata taskResponseMetadata);
    event TaskChallengedSuccessfully(uint32 indexed taskIndex, address indexed challenger);
    event TaskChallengedUnsuccessfully(uint32 indexed taskIndex, address indexed challenger);
    event AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator);

    // task data structure
    struct Task {
        address sourceStateManager;     // source chain state manager address
        address user;                   // user address
        bytes32 expectedStateValue;     // state value to prove
        uint256 sourceBlockNumber;      // source chain block number
        bytes32 sourceBlockHash;        // source chain block hash
        uint32 quorumThresholdPercentage;
        bytes quorumNumbers;
        uint32 taskCreatedBlock;
    }

    // task response data
    struct TaskResponse {
        uint32 referenceTaskIndex;      // task index
        bytes32 actualStateValue;       // actual state value
        IStateManager.StateType stateType; // state type
        bytes stateProof;               // state existence proof
        bytes blockProof;               // block existence proof
    }

    // task response metadata
    struct TaskResponseMetadata {
        uint32 taskRespondedBlock;
        bytes32 hashOfNonSigners;
    }

    // respond to state proof task
    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse,
        IBLSSignatureChecker.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external;

    // challenge task response
    function raiseAndResolveChallenge(
        Task calldata task,
        TaskResponse calldata taskResponse,
        TaskResponseMetadata calldata taskResponseMetadata,
        IBLSSignatureChecker.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external;

    // view functions
    function taskNumber() external view returns (uint32);
    function getTaskResponseWindowBlock() external view returns (uint32);
}
