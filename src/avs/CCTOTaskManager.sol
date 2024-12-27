// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@eigenlayer/contracts/permissions/Pausable.sol";
import "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {BLSApkRegistry} from "@eigenlayer-middleware/src/BLSApkRegistry.sol";
import {RegistryCoordinator} from "@eigenlayer-middleware/src/RegistryCoordinator.sol";
import {
    BLSSignatureChecker,
    IRegistryCoordinator
} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "@eigenlayer-middleware/src/OperatorStateRetriever.sol";
import "@eigenlayer-middleware/src/libraries/BN254.sol";
import "./ICCTOTaskManager.sol";
import "../state-manager/IStateManager.sol";
import {IBLSSignatureChecker} from "@eigenlayer-middleware/src/BLSSignatureChecker.sol";

contract CCTOTaskManager is
    ICCTOTaskManager,
    Initializable,
    OwnableUpgradeable,
    Pausable,
    BLSSignatureChecker,
    OperatorStateRetriever
{
    using BN254 for BN254.G1Point;


    uint32 public immutable TASK_RESPONSE_WINDOW_BLOCK;
    uint32 public constant TASK_CHALLENGE_WINDOW_BLOCK = 100;
    uint256 internal constant THRESHOLD_DENOMINATOR = 100;

    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(uint32 => bytes32) public allTaskResponses;
    mapping(uint32 => bool) public taskSuccessfullyChallenged;
    address public aggregator;

    modifier onlyAggregator() {
        if (msg.sender != aggregator) {
            revert CCTOTaskManager__OnlyAggregator();
        }
        _;
    }

    constructor(
        IRegistryCoordinator _registryCoordinator,
        uint32 _taskResponseWindowBlock
    ) BLSSignatureChecker(_registryCoordinator) {
        TASK_RESPONSE_WINDOW_BLOCK = _taskResponseWindowBlock;
    }

    function initialize(
        IPauserRegistry _pauserRegistry,
        address initialOwner,
        address _aggregator,
        address _stateManager
    ) public initializer {
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
        _setAggregator(_aggregator);
    }

    function setAggregator(address newAggregator) external onlyOwner {
        _setAggregator(newAggregator);
    }

    function respondToTask(
        Task calldata task,
        TaskResponse calldata taskResponse,
        IBLSSignatureChecker.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external onlyAggregator {
        uint32 taskCreatedBlock = task.taskCreatedBlock;
        bytes calldata quorumNumbers = task.quorumNumbers;
        uint32 quorumThresholdPercentage = task.quorumThresholdPercentage;

        // Check task hash
        if (keccak256(abi.encode(task)) != allTaskHashes[taskResponse.referenceTaskIndex]) {
            revert CCTOTaskManager__TaskHashMismatch();
        }

        // Check response timing
        if (allTaskResponses[taskResponse.referenceTaskIndex] != bytes32(0)) {
            revert CCTOTaskManager__TaskAlreadyResponded();
        }

        if (uint32(block.number) > taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK) {
            revert CCTOTaskManager__TaskResponseTooLate();
        }

        // Verify BLS signatures
        bytes32 message = keccak256(abi.encode(taskResponse));
        
        // Check signatures and threshold
        (QuorumStakeTotals memory quorumStakeTotals, bytes32 hashOfNonSigners) = 
            checkSignatures(message, quorumNumbers, taskCreatedBlock, nonSignerStakesAndSignature);

        // Check quorum thresholds
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            if (quorumStakeTotals.signedStakeForQuorum[i] * THRESHOLD_DENOMINATOR <
                quorumStakeTotals.totalStakeForQuorum[i] * uint8(quorumThresholdPercentage)) {
                revert CCTOTaskManager__QuorumThresholdNotMet();
            }
        }

        // Store response
        TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata({
            taskRespondedBlock: uint32(block.number),
            hashOfNonSigners: hashOfNonSigners
        });

        allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(
            abi.encode(taskResponse, taskResponseMetadata)
        );

        emit TaskResponded(taskResponse, taskResponseMetadata);
    }

    function raiseAndResolveChallenge(
        Task calldata task,
        TaskResponse calldata taskResponse,
        TaskResponseMetadata calldata taskResponseMetadata,
        IBLSSignatureChecker.NonSignerStakesAndSignature calldata nonSignerStakesAndSignature
    ) external {
        uint32 referenceTaskIndex = taskResponse.referenceTaskIndex;

        // Basic checks
        if (allTaskResponses[referenceTaskIndex] == bytes32(0)) {
            revert CCTOTaskManager__TaskNotResponded();
        }
        
        if (allTaskResponses[referenceTaskIndex] != keccak256(abi.encode(taskResponse, taskResponseMetadata))) {
            revert CCTOTaskManager__TaskResponseMismatch();
        }
        
        if (taskSuccessfullyChallenged[referenceTaskIndex]) {
            revert CCTOTaskManager__TaskAlreadyChallenged();
        }
        
        if (uint32(block.number) > taskResponseMetadata.taskRespondedBlock + TASK_CHALLENGE_WINDOW_BLOCK) {
            revert CCTOTaskManager__ChallengePeriodExpired();
        }

        // TODO: Add cross-chain verification logic here
        revert("Cross-chain verification not implemented");
    }

    function _setAggregator(address newAggregator) internal {
        address oldAggregator = aggregator;
        aggregator = newAggregator;
        emit AggregatorUpdated(oldAggregator, newAggregator);
    }

    function taskNumber() external view returns (uint32) {
        return latestTaskNum;
    }

    function getTaskResponseWindowBlock() external view returns (uint32) {
        return TASK_RESPONSE_WINDOW_BLOCK;
    }
}
