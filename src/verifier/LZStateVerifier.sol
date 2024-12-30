// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OAppRead} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppRead.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {MessagingFee} from
    "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    ReadCodecV1,
    EVMCallRequestV1,
    EVMCallComputeV1
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/ReadCodecV1.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IStateManager.sol";
import "../interfaces/IStateDisputeResolver.sol";
import "../interfaces/IBridgeVerifier.sol";

// verifies cross-chain state through LayerZero protocol
contract LZStateVerifier is OAppRead, ReentrancyGuard, IBridgeVerifier {
    // custom errors
    error LZStateVerifier__InvalidResponse();
    error LZStateVerifier__VerificationNotFound();
    error LZStateVerifier__VerificationAlreadyCompleted();
    error LZStateVerifier__InvalidMessageLength();
    error LZStateVerifier__InvalidStateValue();
    error LZStateVerifier__InvalidBlockNumber();
    error LZStateVerifier__InvalidChainId();
    error LZStateVerifier__InsufficientFee();

    // layerzero protocol channel for reading state
    uint32 public constant READ_CHANNEL = 4_294_965_695;
    uint16 public constant READ_MSG_TYPE = 1;

    // stores verification status and result
    struct VerificationData {
        bytes32 stateValue;      // verified state value
        uint256 blockNumber;     // block number of verification
        bool isCompleted;        // whether verification is complete
        bool isVerified;         // whether verification passed
    }

    // verification id => verification data
    mapping(bytes32 => VerificationData) public verifications;

    // emitted when verification is requested
    event StateVerificationRequested(bytes32 indexed verificationId, uint256 blockNumber);
    // emitted when verification is completed
    event StateVerificationCompleted(
        bytes32 indexed verificationId, bytes32 stateValue, bool verified
    );

    // reference to dispute resolver contract
    IStateDisputeResolver public immutable disputeResolver;

    constructor(
        address _endpoint,
        address _owner,
        address _disputeResolver
    ) OAppRead(_endpoint, _owner) {
        if (_disputeResolver == address(0)) {
            revert LZStateVerifier__InvalidStateValue();
        }
        disputeResolver = IStateDisputeResolver(_disputeResolver);
        setReadChannel(READ_CHANNEL, true);
    }

    // generates layerzero command for state verification
    function getCmd(
        uint256 targetChainId,
        uint256 blockNumber,
        address targetAddress
    ) public view returns (bytes memory) {
        address stateManager = disputeResolver.getStateManager(targetChainId);

        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](1);

        bytes memory callData = abi.encodeWithSignature(
            "getStateByBlockNumber(address,uint256)", targetAddress, blockNumber
        );

        readRequests[0] = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: uint32(targetChainId),
            isBlockNum: true,
            blockNumOrTimestamp: uint64(blockNumber),
            confirmations: 15,
            to: stateManager,
            callData: callData
        });

        EVMCallComputeV1 memory computeSettings = EVMCallComputeV1({
            computeSetting: 2,
            targetEid: uint32(targetChainId),
            isBlockNum: true,
            blockNumOrTimestamp: uint64(block.number),
            confirmations: 15,
            to: address(this)
        });

        return ReadCodecV1.encode(0, readRequests, computeSettings);
    }

    // initiates state verification through layerzero
    function verifyState(
        uint256 sourceChainId,
        uint256 blockNumber,
        bytes memory options
    ) external payable override returns (bytes32) {
        if (msg.value == 0) {
            revert LZStateVerifier__InsufficientFee();
        }

        bytes32 verificationId = keccak256(
            abi.encodePacked(sourceChainId, blockNumber, block.timestamp, msg.sender)
        );

        if (verifications[verificationId].isCompleted) {
            revert LZStateVerifier__VerificationAlreadyCompleted();
        }

        verifications[verificationId] = VerificationData({
            stateValue: bytes32(0),
            blockNumber: blockNumber,
            isCompleted: false,
            isVerified: false
        });

        bytes memory cmd = getCmd(sourceChainId, blockNumber, msg.sender);
        _lzSend(READ_CHANNEL, cmd, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit StateVerificationRequested(verificationId, blockNumber);
        return verificationId;
    }

    // decodes state proof from source chain
    function lzMap(
        bytes calldata _request,
        bytes calldata _response
    ) external pure returns (bytes memory) {
        if (_response.length == 0) {
            revert LZStateVerifier__InvalidResponse();
        }
        IStateManager.State memory state = abi.decode(_response, (IStateManager.State));
        return abi.encode(state.value, state.timestamp, state.blockNumber);
    }

    // processes multiple responses (currently only supports single response)
    function lzReduce(
        bytes calldata _cmd,
        bytes[] calldata _responses
    ) external pure returns (bytes memory) {
        if (_responses.length != 1) {
            revert LZStateVerifier__InvalidMessageLength();
        }
        return _responses[0];
    }

    // handles incoming state proof from source chain
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata
    ) internal override {
        (bytes32 stateValue, uint256 timestamp, uint256 blockNumber) =
            abi.decode(_message, (bytes32, uint256, uint256));

        VerificationData storage verification = verifications[_guid];
        verification.stateValue = stateValue;
        verification.isCompleted = true;
        verification.isVerified = true;

        emit StateVerificationCompleted(_guid, stateValue, true);
    }
}
