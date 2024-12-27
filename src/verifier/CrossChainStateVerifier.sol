// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IBridgeVerifier.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/ICrossChainStateVerifier.sol";

contract CrossChainStateVerifier is ICrossChainStateVerifier, Initializable, OwnableUpgradeable {
    IAllocationManager public immutable allocationManager;
    
    // Bridge verifiers for each chain
    mapping(uint256 => IBridgeVerifier) public override bridgeVerifiers;
    
    // Operator state mapping
    mapping(address => OperatorState) public override operators;
    
    // Bond required to submit a challenge
    uint256 public override challengeBond;
    
    // Challenge window in blocks
    uint256 public override challengePeriod;
    
    // New state variables
    uint32 public override currentOperatorSetId;
    IStrategy[] public override slashableStrategies;
    uint256 public override slashAmount; // In WAD format (1e18 = 100%)
    
    // Active challenges
    mapping(bytes32 => Challenge) public override challenges;
    
    constructor(address _allocationManager) {
        allocationManager = IAllocationManager(_allocationManager);
    }
    
    function initialize(
        uint256 _challengeBond,
        uint256 _challengePeriod,
        uint32 _operatorSetId,
        uint256 _slashAmount
    ) external initializer {
        __Ownable_init();
        challengeBond = _challengeBond;
        challengePeriod = _challengePeriod;
        currentOperatorSetId = _operatorSetId;
        slashAmount = _slashAmount;
    }
    
    function setVerifier(uint256 chainId, address verifier) external onlyOwner {
        bridgeVerifiers[chainId] = IBridgeVerifier(verifier);
        emit VerifierSet(chainId, verifier);
    }
    
    function submitChallenge(
        uint256 chainId,
        uint256 blockNumber,
        bytes32 claimedState,
        bytes memory proof,
        address operator
    ) external payable {
        if (msg.value < challengeBond) {
            revert CrossChainStateVerifier__InsufficientBond();
        }
        
        if (!operators[operator].isRegistered) {
            revert CrossChainStateVerifier__OperatorNotRegistered();
        }
        
        bytes32 challengeId = keccak256(abi.encodePacked(
            chainId,
            blockNumber,
            claimedState,
            operator
        ));
        
        if (challenges[challengeId].challenger != address(0)) {
            revert CrossChainStateVerifier__ChallengeAlreadyExists();
        }
        
        IBridgeVerifier verifier = bridgeVerifiers[chainId];
        if (address(verifier) == address(0)) {
            revert CrossChainStateVerifier__NoVerifierConfigured();
        }
        
        bytes32 actualState = verifier.verifyState(
            chainId,
            blockNumber,
            proof
        );
        
        challenges[challengeId] = Challenge({
            challenger: msg.sender,
            deadline: block.number + challengePeriod,
            resolved: false,
            claimedState: claimedState,
            actualState: actualState
        });
        
        emit ChallengeSubmitted(challengeId, msg.sender);
    }
    
    function resolveChallenge(bytes32 challengeId) external {
        Challenge storage challenge = challenges[challengeId];
        
        if (challenge.resolved) {
            revert CrossChainStateVerifier__ChallengeAlreadyResolved();
        }
        
        if (block.number <= challenge.deadline) {
            revert CrossChainStateVerifier__ChallengePeriodActive();
        }
        
        if(challenge.claimedState != challenge.actualState) {
            address operator = address(uint160(uint256(challengeId)));
            _slashOperator(operator, challengeId);
            payable(challenge.challenger).transfer(challengeBond);
        } else {
            payable(challenge.challenger).transfer(challengeBond / 2);
        }
        
        challenge.resolved = true;
        emit ChallengeResolved(challengeId, challenge.claimedState != challenge.actualState);
    }
    
    function setOperatorSetId(uint32 newSetId) external onlyOwner {
        currentOperatorSetId = newSetId;
        emit OperatorSetIdUpdated(newSetId);
    }

    function setSlashableStrategies(IStrategy[] calldata strategies) external onlyOwner {
        if(strategies.length == 0) {
            revert CrossChainStateVerifier__EmptyStrategiesArray();
        }
        delete slashableStrategies;
        for(uint i = 0; i < strategies.length; i++) {
            slashableStrategies.push(strategies[i]);
        }
        emit SlashableStrategiesUpdated(strategies);
    }

    function setSlashAmount(uint256 newAmount) external onlyOwner {
        if(newAmount > 1e18) {
            revert CrossChainStateVerifier__InvalidSlashAmount();
        }
        slashAmount = newAmount;
        emit SlashAmountUpdated(newAmount);
    }

    function _slashOperator(address operator, bytes32 challengeId) internal {
        if(slashableStrategies.length == 0) {
            revert CrossChainStateVerifier__EmptyStrategiesArray();
        }
        
        uint256[] memory wadsToSlash = new uint256[](slashableStrategies.length);
        for(uint i = 0; i < slashableStrategies.length; i++) {
            wadsToSlash[i] = slashAmount;
        }

        IAllocationManager.SlashingParams memory params = IAllocationManager.SlashingParams({
            operator: operator,
            operatorSetId: currentOperatorSetId,
            strategies: slashableStrategies,
            wadsToSlash: wadsToSlash,
            description: string(abi.encodePacked(
                "Cross chain state verification failure-Challenge ID: ",
                challengeId
            ))
        });

        allocationManager.slashOperator(address(this), params);
        
        OperatorState storage state = operators[operator];
        state.isSlashed = true;
        
        emit OperatorSlashed(operator, challengeId);
    }
}