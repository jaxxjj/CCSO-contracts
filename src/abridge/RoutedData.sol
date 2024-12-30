// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RoutedData Library
/// @notice A library for encoding and decoding data with prepended "from" and "to" addresses
library RoutedData {
    /// @dev Error thrown when the data length is insufficient for decoding
    /// @param length The actual length of the data
    error InsufficientDataLength(uint64 length);

    /// @notice Encodes two addresses and data into a single byte array
    /// @param from The sender address to prepend
    /// @param to The recipient address to prepend
    /// @param data The data to encode
    /// @return A byte array containing the encoded addresses and data
    function encode(address from, address to, bytes memory data) internal pure returns (bytes memory) {
        // Prepend the two addresses to the data using abi.encodePacked
        return abi.encodePacked(from, to, data);
    }

    /// @notice Decodes a byte array into two addresses and the remaining data
    /// @param data The byte array to decode
    /// @return from The extracted sender address
    /// @return to The extracted recipient address
    /// @return remainingData The remaining data after extracting the addresses
    function decode(bytes memory data) internal pure returns (address from, address to, bytes memory remainingData) {
        if (data.length < 40) {
            revert InsufficientDataLength(uint64(data.length));
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Load the first 20 bytes (from address) from the start of data
            from := mload(add(data, 20))

            // Load the next 20 bytes (to address)
            to := mload(add(data, 40))

            // Set remainingData to point to the location after the first 40 bytes (2 addresses)
            remainingData := add(data, 40)

            // Update the length of remainingData (total length minus 40 bytes for the two addresses)
            mstore(remainingData, sub(mload(data), 40))
        }
    }
}
