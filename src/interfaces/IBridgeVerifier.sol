// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBridgeVerifier {
    // verify state on source chain
    function verifyState(
        uint256 sourceChainId,
        uint256 blockNumber,
        bytes memory options
    ) external payable returns (bytes32);
}
