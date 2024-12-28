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
import "../verifier/CrossChainStateVerifier.sol";
import "../interfaces/ICCSOServiceManager.sol";

contract CCSOServiceManager is 
    Initializable,
    ECDSAServiceManagerBase, 
    PausableUpgradeable,
    ICCSOServiceManager 
{
    using ECDSAUpgradeable for bytes32;

    uint256 public constant CHALLENGE_BOND = 2 ether; 
    // Task tracking
    uint32 public latestTaskNum;
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes32)) public operatorResponses;
    
    // Verifier reference
    CrossChainStateVerifier public immutable stateVerifier;
    

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager,
        address _stateVerifier
    ) ECDSAServiceManagerBase(
        _avsDirectory,
        _stakeRegistry,
        _rewardsCoordinator,
        _delegationManager
    ) {
        _disableInitializers();
        stateVerifier = CrossChainStateVerifier(_stateVerifier);
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
        if (operatorResponses[msg.sender][referenceTaskIndex] != bytes32(0)) {
            revert CCSOServiceManager__TaskAlreadyResponded();
        }

        bytes32 messageHash = keccak256(abi.encodePacked(
            referenceTaskIndex,
            task.chainId,
            task.blockNumber,
            task.stateValue
        ));

        if (allTaskHashes[referenceTaskIndex] != bytes32(0)) {
            if (keccak256(abi.encode(task)) != allTaskHashes[referenceTaskIndex]) {
                revert CCSOServiceManager__TaskHashMismatch();
            }
        }

        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;
        
        if (magicValue != ECDSAStakeRegistry(stakeRegistry).isValidSignature(
            ethSignedMessageHash,
            signature
        )) {
            revert CCSOServiceManager__InvalidSignature();
        }

        operatorResponses[msg.sender][referenceTaskIndex] = task.stateValue;
        
        if (referenceTaskIndex >= latestTaskNum) {
            allTaskHashes[referenceTaskIndex] = messageHash;
            latestTaskNum = referenceTaskIndex + 1;
        }

        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }

    function submitStateChallenge(
        uint256 chainId,
        uint256 blockNumber,
        bytes32 claimedState,
        bytes memory proof,
        address operator
    ) external payable override whenNotPaused {
        if (msg.value < CHALLENGE_BOND) {
            revert CCSOServiceManager__InsufficientChallengeBond();
        }

        try stateVerifier.submitChallenge{value: msg.value}(
            chainId,
            blockNumber,
            claimedState,
            proof,
            operator
        ) {
            emit TaskChallenged(chainId, blockNumber, claimedState, operator);
        } catch {
            revert CCSOServiceManager__InvalidChallenge();
        }
    }

    // View functions
    function getTaskResponse(address operator, uint32 taskNum) external view returns (bytes32) {
        return operatorResponses[operator][taskNum];
    }

    function getTaskHash(uint32 taskNum) external view returns (bytes32) {
        return allTaskHashes[taskNum];
    }
}
