// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {ECDSAUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
import {IPauserRegistry} from "@eigenlayer/contracts/interfaces/IPauserRegistry.sol";
import {ISignatureUtils} from "@eigenlayer/contracts/interfaces/ISignatureUtils.sol";
import {IStateDisputeResolver} from "../interfaces/IStateDisputeResolver.sol";
import "../interfaces/ICCSOServiceManager.sol";

contract CCSOServiceManager is
    Initializable,
    ECDSAServiceManagerBase,
    PausableUpgradeable,
    ICCSOServiceManager
{
    using ECDSAUpgradeable for bytes32;

    // Task tracking
    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => TaskResponse)) private _taskResponses;

    // State variables
    IStateDisputeResolver public immutable disputeResolver;

    modifier onlyDisputeResolver() {
        if (msg.sender != address(disputeResolver)) {
            revert CCSOServiceManager__CallerNotDisputeResolver();
        }
        _;
    }

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _disputeResolver
    )
        ECDSAServiceManagerBase(_avsDirectory, _stakeRegistry, _rewardsCoordinator, _delegationManager)
    {
        _disableInitializers();
        disputeResolver = IStateDisputeResolver(_disputeResolver);
    }

    function initialize(
        address initialOwner,
        address initialRewardsInitiator,
        IPauserRegistry pauserRegistry
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ServiceManagerBase_init(initialOwner, address(pauserRegistry));
        _setRewardsInitiator(initialRewardsInitiator);
    }

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        bytes memory signature
    ) external override whenNotPaused {
        if (_taskResponses[msg.sender][referenceTaskIndex].resolved) {
            revert CCSOServiceManager__TaskAlreadyResponded();
        }

        bytes32 messageHash = keccak256(
            abi.encodePacked(referenceTaskIndex, task.chainId, task.blockNumber, task.stateValue)
        );

        if (allTaskHashes[referenceTaskIndex] != bytes32(0)) {
            if (keccak256(abi.encode(task)) != allTaskHashes[referenceTaskIndex]) {
                revert CCSOServiceManager__TaskHashMismatch();
            }
        }

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;

        if (
            magicValue
                != ECDSAStakeRegistry(stakeRegistry).isValidSignature(ethSignedMessageHash, signature)
        ) {
            revert CCSOServiceManager__InvalidSignature();
        }

        // record response (Optimistic)
        _taskResponses[msg.sender][referenceTaskIndex] = TaskResponse({
            stateValue: task.stateValue,
            responseBlock: block.number,
            challenged: false,
            resolved: false
        });

        if (referenceTaskIndex >= latestTaskNum) {
            allTaskHashes[referenceTaskIndex] = messageHash;
            latestTaskNum = referenceTaskIndex + 1;
        }

        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }

    function handleChallengeResult(
        address operator,
        uint32 taskNum,
        bool challengeSuccessful
    ) external onlyDisputeResolver {
        TaskResponse storage response = _taskResponses[operator][taskNum];
        if (!response.challenged) {
            revert CCSOServiceManager__TaskNotChallenged();
        }

        response.resolved = true;

        if (challengeSuccessful) {
            delete response.stateValue;
        }

        emit ChallengeResolved(operator, taskNum, challengeSuccessful);
    }
    // View functions

    function taskResponses(
        address operator,
        uint32 taskNum
    ) external view override returns (TaskResponse memory) {
        return _taskResponses[operator][taskNum];
    }

    function getTaskHash(
        uint32 taskNum
    ) external view returns (bytes32) {
        return allTaskHashes[taskNum];
    }

    function getTaskResponse(
        address operator, 
        uint32 taskNum
    ) external view override returns (bytes32) {
        return _taskResponses[operator][taskNum].stateValue;
    }

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external override onlyStakeRegistry {
        _registerOperatorToAVS(operator, operatorSignature);
    }
}
