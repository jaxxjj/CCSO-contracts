// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin-v5.0.0/contracts/access/Ownable2Step.sol";
import { IAbridgeMessageHandler } from "../abridge/IAbridge.sol";
import { IAbridge } from "../abridge/IAbridge.sol";
import "../interfaces/IStateManager.sol";

// verifier for remote chains that handles verification requests
contract RemoteChainVerifier is Ownable2Step, IAbridgeMessageHandler {
    error RemoteChainVerifier__InvalidResponse();
    error RemoteChainVerifier__StateManagerNotSet();
    error RemoteChainVerifier__InvalidStateManager();
    error RemoteChainVerifier__InvalidMainChainId();
    error RemoteChainVerifier__OnlyAbridge();
    
    IAbridge public immutable abridge;
    IStateManager public stateManager;
    uint256 public immutable mainChainId;
    
    event StateManagerUpdated(address indexed newStateManager);
    event VerificationProcessed(bytes32 indexed challengeId, bytes32 actualState, bool verified);
    
    modifier onlyAbridge() {
        if (msg.sender != address(abridge)) {
            revert RemoteChainVerifier__OnlyAbridge();
        }
        _;
    }
    
    constructor(
        address _abridge, 
        address _stateManager,
        uint256 _mainChainId,
        address _owner
    ) Ownable(_owner) {
        if (_abridge == address(0)) revert RemoteChainVerifier__InvalidResponse();
        if (_mainChainId == 0) revert RemoteChainVerifier__InvalidMainChainId();
        
        abridge = IAbridge(_abridge);
        if (_stateManager != address(0)) {
            stateManager = IStateManager(_stateManager);
        }
        mainChainId = _mainChainId;
    }

    function setStateManager(address _stateManager) external onlyOwner {
        if (_stateManager == address(0)) revert RemoteChainVerifier__InvalidStateManager();
        stateManager = IStateManager(_stateManager);
        emit StateManagerUpdated(_stateManager);
    }

    // handle verification request from main chain
    function handleMessage(
        address from,
        bytes calldata message,
        bytes32 guid
    ) external override onlyAbridge returns (bytes4) {
        // check state manager is set
        if (address(stateManager) == address(0)) {
            revert RemoteChainVerifier__StateManagerNotSet();
        }
        
        // decode verification request
        (bytes32 challengeId, address user, uint256 key, uint256 blockNumber) = 
            abi.decode(message, (bytes32, address, uint256, uint256));
            
        // get current value info
        IStateManager.ValueInfo memory currentValue = stateManager.getCurrentValue(user, key);
        if (!currentValue.exists) {
            // return unverified if state does not exist
            bytes memory response = abi.encode(challengeId, bytes32(0), false);
            abridge.send{value: address(this).balance}(from, 200000, response);
            emit VerificationProcessed(challengeId, bytes32(0), false);
            return IAbridgeMessageHandler.handleMessage.selector;
        }

        // get historical state and verify
        IStateManager.History memory history = stateManager.getHistoryAtBlock(user, key, blockNumber);
        bytes32 actualState = bytes32(history.value);
        
        // verify state based on type
        bool verified = true;
        if (IStateManager.StateType(currentValue.stateType) == IStateManager.StateType.MONOTONIC_INCREASING) {
            verified = history.value <= currentValue.value;
        } else if (IStateManager.StateType(currentValue.stateType) == IStateManager.StateType.MONOTONIC_DECREASING) {
            verified = history.value >= currentValue.value;
        }
        
        // send verification result back to main chain
        bytes memory response = abi.encode(challengeId, actualState, verified);
        abridge.send{value: address(this).balance}(from, 200000, response);
        
        emit VerificationProcessed(challengeId, actualState, verified);
        return IAbridgeMessageHandler.handleMessage.selector;
    }


    receive() external payable {}
}