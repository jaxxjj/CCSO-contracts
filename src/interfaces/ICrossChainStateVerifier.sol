// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IBridgeVerifier.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategy.sol";

interface ICrossChainStateVerifier {
    // Custom errors
    error CrossChainStateVerifier__NoVerifierConfigured();
    error CrossChainStateVerifier__OperatorNotRegistered();
    error CrossChainStateVerifier__ChallengeAlreadyExists();
    error CrossChainStateVerifier__ChallengePeriodActive();
    error CrossChainStateVerifier__ChallengeAlreadyResolved();
    error CrossChainStateVerifier__InsufficientBond();
    error CrossChainStateVerifier__EmptyStrategiesArray();
    error CrossChainStateVerifier__InvalidSlashAmount();
    
    // Structs
    struct OperatorState {
        bool isRegistered;    // whether operator is registered
        bool isSlashed;       // whether operator has been slashed
        uint256 stake;        // amount staked by operator
    }
    
    struct Challenge {
        address challenger;   // address that submitted the challenge
        uint256 deadline;     // block number when challenge expires
        bool resolved;        // whether challenge has been resolved
        bytes32 claimedState; // state claimed by operator
        bytes32 actualState;  // actual state verified on source chain
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
        address operator
    ) external payable;
    
    function resolveChallenge(bytes32 challengeId) external;
    
    function setOperatorSetId(uint32 newSetId) external;
    
    function setSlashableStrategies(IStrategy[] calldata strategies) external;
    
    function setSlashAmount(uint256 newAmount) external;

    // View functions
    function bridgeVerifiers(uint256 chainId) external view returns (IBridgeVerifier);
    function operators(address operator) external view returns (bool isRegistered, bool isSlashed, uint256 stake);
    function challenges(bytes32 challengeId) external view returns (
        address challenger,
        uint256 deadline,
        bool resolved,
        bytes32 claimedState,
        bytes32 actualState
    );
    function challengeBond() external view returns (uint256);
    function challengePeriod() external view returns (uint256);
    function currentOperatorSetId() external view returns (uint32);
    function slashableStrategies(uint256 index) external view returns (IStrategy);
    function slashAmount() external view returns (uint256);
} 