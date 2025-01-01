// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import {ECDSAServiceManagerBase} from
    "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {ECDSAUpgradeable} from
    "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from
    "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import {PausableUpgradeable} from
    "@openzeppelin-upgrades/contracts/security/PausableUpgradeable.sol";
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
        bytes memory signatureData
    ) external override whenNotPaused {
        // Decode signature data
        (address[] memory operators,,) = abi.decode(signatureData, (address[], bytes[], uint32));

        // Check if any of the operators has already responded
        uint256 operatorsLength = operators.length;
        for (uint256 i = 0; i < operatorsLength;) {
            if (_taskResponses[operators[i]][referenceTaskIndex].resolved) {
                revert CCSOServiceManager__TaskAlreadyResponded();
            }
            unchecked {
                ++i;
            }
        }

        bytes32 messageHash = keccak256(
            abi.encodePacked(referenceTaskIndex, task.chainId, task.blockNumber, task.value)
        );

        if (allTaskHashes[referenceTaskIndex] != bytes32(0)) {
            if (keccak256(abi.encode(task)) != allTaskHashes[referenceTaskIndex]) {
                revert CCSOServiceManager__TaskHashMismatch();
            }
        }

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;

        // verify quorum signatures
        if (
            magicValue
                != ECDSAStakeRegistry(stakeRegistry).isValidSignature(
                    ethSignedMessageHash, signatureData
                )
        ) {
            revert CCSOServiceManager__InvalidSignature();
        }
        // record response for each signing operator
        for (uint256 i = 0; i < operatorsLength; ) {
            _taskResponses[operators[i]][referenceTaskIndex] = TaskResponse({
                task: task,
                responseBlock: block.number,
                challenged: false,
                resolved: false
            });
            unchecked {
                ++i;
            }
        }

        if (referenceTaskIndex >= latestTaskNum) {
            allTaskHashes[referenceTaskIndex] = messageHash;
            latestTaskNum = referenceTaskIndex + 1;
        }

        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }

    function handleChallengeSubmission(
        address operator,
        uint32 taskNum
    ) external onlyDisputeResolver {
        TaskResponse storage response = _taskResponses[operator][taskNum];
        if (response.challenged) {
            revert CCSOServiceManager__TaskAlreadyChallenged();
        }
        response.challenged = true;
        emit TaskChallenged(operator, taskNum);
    }

    function handleChallengeResolution(
        address operator,
        uint32 taskNum,
        bool challengeSuccessful
    ) external onlyDisputeResolver {
        TaskResponse storage response = _taskResponses[operator][taskNum];
        if (!response.challenged) {
            revert CCSOServiceManager__TaskNotChallenged();
        }
        if (response.resolved) {
            revert CCSOServiceManager__TaskAlreadyResolved();
        }
        
        response.resolved = true;
        emit ChallengeResolved(operator, taskNum, challengeSuccessful);
    }

    function getTaskHash(
        uint32 taskNum
    ) external view returns (bytes32) {
        return allTaskHashes[taskNum];
    }

    function getTaskResponse(
        address operator,
        uint32 taskNum
    ) external view override returns (TaskResponse memory) {
        return _taskResponses[operator][taskNum];
    }

    function registerOperatorToAVS(
        address operator,
        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature
    ) external override onlyStakeRegistry {
        _registerOperatorToAVS(operator, operatorSignature);
    }
}
