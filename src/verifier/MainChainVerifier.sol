// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin-v5.0.0/contracts/access/Ownable2Step.sol";
import { IAbridgeMessageHandler } from "../abridge/IAbridge.sol";
import { IAbridge } from "../abridge/IAbridge.sol";
import "../interfaces/IStateManager.sol";

// verifier for main chain that only receives verification results
contract MainChainVerifier is Ownable2Step, IAbridgeMessageHandler {
    error MainChainVerifier__InvalidResponse();
    error MainChainVerifier__VerificationNotFound();
    error MainChainVerifier__OnlyDisputeResolver();
    error MainChainVerifier__OnlyAbridge();
    
    address public immutable disputeResolver;
    IAbridge public immutable abridge;
    
    event VerificationResultReceived(bytes32 indexed challengeId, bytes32 actualState, bool verified);
    
    modifier onlyAbridge() {
        if (msg.sender != address(abridge)) {
            revert MainChainVerifier__OnlyAbridge();
        }
        _;
    }

    constructor(address _abridge, address _disputeResolver, address _owner) Ownable(_owner) {
        if (_abridge == address(0) || _disputeResolver == address(0)) {
            revert MainChainVerifier__InvalidResponse();
        }
        abridge = IAbridge(_abridge);
        disputeResolver = _disputeResolver;
    }

    // only receive verification results
    function handleMessage(
        address from,
        bytes calldata message,
        bytes32 guid
    ) external override onlyAbridge returns (bytes4) {
        // decode verification result
        (bytes32 challengeId, bytes32 actualState, bool verified) = 
            abi.decode(message, (bytes32, bytes32, bool));
            
        // update verification result in dispute resolver
        IStateDisputeResolver(disputeResolver).updateChallengeVerification(
            challengeId,
            actualState,
            verified
        );
        
        emit VerificationResultReceived(challengeId, actualState, verified);
        return IAbridgeMessageHandler.handleMessage.selector;
    }

    // main chain does not implement verify state
    function verifyState(
        uint256,
        uint256,
        bytes memory
    ) external payable override returns (bytes32) {
        revert MainChainVerifier__InvalidResponse();
    }

    receive() external payable {}
}