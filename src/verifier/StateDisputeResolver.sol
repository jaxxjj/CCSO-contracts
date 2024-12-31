// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IBridgeVerifier.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IStateDisputeResolver.sol";
import "../interfaces/ICCSOServiceManager.sol";

contract StateDisputeResolver is IStateDisputeResolver, Initializable, OwnableUpgradeable {


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

    // Add mapping for StateManager addresses
    mapping(uint256 => address) public override stateManagers;

    // Add ServiceManager reference
    ICCSOServiceManager public serviceManager;

    // Add modifier for ServiceManager only calls
    modifier onlyServiceManager() {
        if (msg.sender != address(serviceManager)) {
            revert StateDisputeResolver__CallerNotServiceManager();
        }
        _;
    }

    // Add challenge window
    uint256 public constant CHALLENGE_WINDOW = 7200; // 24 hours

    // 添加MainChainVerifier权限检查
    modifier onlyMainChainVerifier() {
        if (msg.sender != address(bridgeVerifiers[mainChainId])) {
            revert StateDisputeResolver__CallerNotMainChainVerifier();
        }
        _;
    }

    constructor(
        address _allocationManager
    ) {
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

    // sets verifier for specific chain
    function setVerifier(uint256 chainId, address verifier) external onlyOwner {
        bridgeVerifiers[chainId] = IBridgeVerifier(verifier);
        emit VerifierSet(chainId, verifier);
    }

    // submit challenge for invalid state claim
    function submitChallenge(
        address operator,
        uint32 taskNum
    ) external payable {
        // check bond amount
        if (msg.value < challengeBond) {
            revert StateDisputeResolver__InsufficientBond();
        }

        // get task response
        ICCSOServiceManager.TaskResponse memory response = 
            ICCSOServiceManager(serviceManager).getTaskResponse(operator, taskNum);
        
        // verify task exists
        if (!response.exist) {
            revert StateDisputeResolver__TaskNotFound();
        }

        // verify not already challenged or resolved
        if (response.challenged || response.resolved) {
            revert StateDisputeResolver__TaskAlreadyProcessed();
        }

        // verify within challenge window
        if (block.number > response.responseBlock + CHALLENGE_WINDOW) {
            revert StateDisputeResolver__ChallengeWindowExpired();
        }

        if (!operators[operator].isRegistered) {
            revert StateDisputeResolver__OperatorNotRegistered();
        }

        bytes32 challengeId = keccak256(
            abi.encodePacked(
                operator,
                taskNum
            )
        );

        if (challenges[challengeId].challenger != address(0)) {
            revert StateDisputeResolver__ChallengeAlreadyExists();
        }

        IBridgeVerifier verifier = bridgeVerifiers[response.task.chainId];
        if (address(verifier) == address(0)) {
            revert StateDisputeResolver__NoVerifierConfigured();
        }

        challenges[challengeId] = Challenge({
            challenger: msg.sender,
            deadline: block.number + challengePeriod,
            resolved: false,
            claimedState: bytes32(response.task.value), // 存储operator提交的值
            actualState: bytes32(0),  // 等待verifier返回实际状态
            verified: false
        });

        // 标记TaskResponse为challenged
        ICCSOServiceManager(serviceManager).handleChallengeResult(
            operator,
            taskNum,
            false  // 初始设置为未验证
        );


        emit ChallengeSubmitted(challengeId, msg.sender);
    }

    // resolves submitted challenge
    function resolveChallenge(
        bytes32 challengeId
    ) external {
        Challenge storage challenge = challenges[challengeId];

        if (challenge.resolved) {
            revert StateDisputeResolver__ChallengeAlreadyResolved();
        }

        if (block.number <= challenge.deadline) {
            revert StateDisputeResolver__ChallengePeriodActive();
        }

        if (challenge.claimedState != challenge.actualState) {
            address operator = address(uint160(uint256(challengeId)));
            _slashOperator(operator, challengeId);
            payable(challenge.challenger).transfer(challengeBond);
        } else {
            payable(challenge.challenger).transfer(challengeBond / 2);
        }

        challenge.resolved = true;
        emit ChallengeResolved(challengeId, challenge.claimedState != challenge.actualState);
    }

    function setOperatorSetId(
        uint32 newSetId
    ) external onlyOwner {
        currentOperatorSetId = newSetId;
        emit OperatorSetIdUpdated(newSetId);
    }

    function setSlashableStrategies(
        IStrategy[] calldata strategies
    ) external onlyOwner {
        if (strategies.length == 0) {
            revert StateDisputeResolver__EmptyStrategiesArray();
        }
        delete slashableStrategies;
        for (uint256 i = 0; i < strategies.length; i++) {
            slashableStrategies.push(strategies[i]);
        }
        emit SlashableStrategiesUpdated(strategies);
    }

    function setSlashAmount(
        uint256 newAmount
    ) external onlyOwner {
        if (newAmount > 1e18) {
            revert StateDisputeResolver__InvalidSlashAmount();
        }
        slashAmount = newAmount;
        emit SlashAmountUpdated(newAmount);
    }

    // internal function to slash operator
    function _slashOperator(address operator, bytes32 challengeId) internal {
        if (slashableStrategies.length == 0) {
            revert StateDisputeResolver__EmptyStrategiesArray();
        }

        uint256[] memory wadsToSlash = new uint256[](slashableStrategies.length);
        for (uint256 i = 0; i < slashableStrategies.length; i++) {
            wadsToSlash[i] = slashAmount;
        }

        IAllocationManager.SlashingParams memory params = IAllocationManager.SlashingParams({
            operator: operator,
            operatorSetId: currentOperatorSetId,
            strategies: slashableStrategies,
            wadsToSlash: wadsToSlash,
            description: string(
                abi.encodePacked("Cross chain state verification failure-Challenge ID: ", challengeId)
            )
        });

        allocationManager.slashOperator(address(this), params);

        OperatorState storage state = operators[operator];
        state.isSlashed = true;

        emit OperatorSlashed(operator, challengeId);
    }

    function setStateManager(uint256 chainId, address stateManager) external onlyOwner {
        if (stateManager == address(0)) {
            revert StateDisputeResolver__InvalidStateManagerAddress();
        }
        stateManagers[chainId] = stateManager;
        emit StateManagerSet(chainId, stateManager);
    }

    function getStateManager(
        uint256 chainId
    ) external view returns (address) {
        address stateManager = stateManagers[chainId];
        if (stateManager == address(0)) {
            revert StateDisputeResolver__StateManagerNotConfigured();
        }
        return stateManager;
    }

    function setServiceManager(
        address _serviceManager
    ) external onlyOwner {
        require(_serviceManager != address(0), "Invalid address");
        serviceManager = ICCSOServiceManager(_serviceManager);
        emit ServiceManagerSet(_serviceManager);
    }

    // update verification result from main chain verifier
    function updateChallengeVerification(
        bytes32 challengeId,
        bytes32 actualState,
        bool verified
    ) external onlyMainChainVerifier {
        Challenge storage challenge = challenges[challengeId];
        if (challenge.challenger == address(0)) {
            revert StateDisputeResolver__ChallengeNotFound();
        }
        
        challenge.actualState = actualState;
        challenge.verified = verified;
        
        emit ChallengeVerificationUpdated(challengeId, actualState, verified);
    }
}
