// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IBridgeVerifier.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategy.sol";

interface IStateDisputeResolver {
    // Custom errors
    error StateDisputeResolver__NoVerifierConfigured();
    error StateDisputeResolver__OperatorNotRegistered();
    error StateDisputeResolver__ChallengeAlreadyExists();
    error StateDisputeResolver__ChallengePeriodActive();
    error StateDisputeResolver__ChallengeAlreadyResolved();
    error StateDisputeResolver__InsufficientBond();
    error StateDisputeResolver__EmptyStrategiesArray();
    error StateDisputeResolver__InvalidSlashAmount();
    error StateDisputeResolver__InvalidStateManagerAddress();
    error StateDisputeResolver__StateManagerNotConfigured();
    error StateDisputeResolver__CallerNotServiceManager();
    error StateDisputeResolver__ChallengeWindowExpired();

    // Structs
    struct OperatorState {
        bool isRegistered; // whether operator is registered
        bool isSlashed; // whether operator has been slashed
        uint256 stake; // amount staked by operator
    }

    struct Challenge {
        address challenger; // address that submitted the challenge
        uint256 deadline; // block number when challenge expires
        bool resolved; // whether challenge has been resolved
        bytes32 claimedState; // state claimed by operator
        bytes32 actualState; // actual state verified on source chain
    }

    // Events
    event VerifierSet(uint256 chainId, address verifier);
    event ChallengePeriodSet(uint256 newPeriod);
    event ChallengeBondSet(uint256 newBond);
    event ChallengeSubmitted(bytes32 indexed challengeId, address indexed challenger);
    event ChallengeResolved(bytes32 indexed challengeId, bool slashed);
    event OperatorSetIdUpdated(uint32 newSetId);
    event SlashableStrategiesUpdated(IStrategy[] strategies);
    event SlashAmountUpdated(uint256 newAmount);
    event OperatorSlashed(address operator, bytes32 challengeId);
    event StateManagerSet(uint256 indexed chainId, address indexed stateManager);
    event ServiceManagerSet(address indexed serviceManager);

    // Core functions
    function initialize(
        uint256 _challengeBond,
        uint256 _challengePeriod,
        uint32 _operatorSetId,
        uint256 _slashAmount
    ) external;

    function setVerifier(uint256 chainId, address verifier) external;

    function submitChallenge(
        uint256 chainId,
        uint256 blockNumber,
        bytes32 claimedState,
        bytes memory proof,
        address operator,
        uint32 taskNum
    ) external payable;

    function resolveChallenge(
        bytes32 challengeId
    ) external;

    function setOperatorSetId(
        uint32 newSetId
    ) external;

    function setSlashableStrategies(
        IStrategy[] calldata strategies
    ) external;

    function setSlashAmount(
        uint256 newAmount
    ) external;

    // View functions
    function bridgeVerifiers(
        uint256 chainId
    ) external view returns (IBridgeVerifier);
    function operators(
        address operator
    ) external view returns (bool isRegistered, bool isSlashed, uint256 stake);
    function challenges(
        bytes32 challengeId
    )
        external
        view
        returns (
            address challenger,
            uint256 deadline,
            bool resolved,
            bytes32 claimedState,
            bytes32 actualState
        );
    function challengeBond() external view returns (uint256);
    function challengePeriod() external view returns (uint256);
    function currentOperatorSetId() external view returns (uint32);
    function slashableStrategies(
        uint256 index
    ) external view returns (IStrategy);
    function slashAmount() external view returns (uint256);

    // New functions
    function setStateManager(uint256 chainId, address stateManager) external;
    function getStateManager(
        uint256 chainId
    ) external view returns (address);
    function stateManagers(
        uint256 chainId
    ) external view returns (address);
}
