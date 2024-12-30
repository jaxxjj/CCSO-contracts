// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable2Step } from "@openzeppelin-v5.1.0/contracts/access/Ownable2Step.sol";
import { IAbridgeMessageHandler } from "../abridge/IAbridge.sol";
import { IAbridge } from "../abridge/IAbridge.sol";
import "../interfaces/IStateManager.sol";
import "../interfaces/IBridgeVerifier.sol";

contract LZStateVerifier is Ownable2Step, IAbridgeMessageHandler, IBridgeVerifier {
    error LZStateVerifier__InvalidResponse();
    error LZStateVerifier__VerificationNotFound();
    error LZStateVerifier__InsufficientFee();
    error LZStateVerifier__InvalidStateValue();
    
    struct VerificationData {
        address user;
        uint256 key;
        uint256 value;
        uint256 blockNumber;
        bool isCompleted;
        bool isVerified;
        bytes32 actualState;
    }

    IAbridge public immutable abridge;
    mapping(bytes32 => VerificationData) public verifications;
    
    event StateVerificationRequested(bytes32 indexed verificationId, uint256 blockNumber);
    event StateVerificationCompleted(bytes32 indexed verificationId, bytes32 actualState, bool verified);

    constructor(address _abridge, address _owner) Ownable(_owner) {
        abridge = IAbridge(_abridge);
    }

    function verifyState(
        uint256 sourceChainId,
        uint256 blockNumber,
        bytes memory proof
    ) external payable override returns (bytes32) {
        if (msg.value == 0) revert LZStateVerifier__InsufficientFee();

        (address user, uint256 key, uint256 value) = abi.decode(proof, (address, uint256, uint256));
        
        bytes32 verificationId = keccak256(
            abi.encodePacked(sourceChainId, blockNumber, user, key, value)
        );

        verifications[verificationId] = VerificationData({
            user: user,
            key: key,
            value: value,
            blockNumber: blockNumber,
            isCompleted: false,
            isVerified: false,
            actualState: bytes32(0)
        });

        bytes memory message = abi.encode(verificationId, user, key, blockNumber);
        abridge.send{value: msg.value}(address(this), 200000, message);

        emit StateVerificationRequested(verificationId, blockNumber);
        return verificationId;
    }

    function handleMessage(
        address from,
        bytes calldata message,
        bytes32 guid
    ) external override returns (bytes4) {
        (bytes32 verificationId, bytes32 actualState, bool verified) = 
            abi.decode(message, (bytes32, bytes32, bool));

        VerificationData storage verification = verifications[verificationId];
        verification.isCompleted = true;
        verification.isVerified = verified;
        verification.actualState = actualState;

        emit StateVerificationCompleted(verificationId, actualState, verified);
        
        return IAbridgeMessageHandler.handleMessage.selector;
    }
}
