// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IStateManager
/// @notice defines interface for state validation and management
interface IStateManager {
    // Custom Errors
    error StateManager__InvalidStateType();
    error StateManager__ValueNotMonotonic();
    error StateManager__InvalidBlockRange();
    error StateManager__BlockNotYetMined(uint256 blockNumber);
    error StateManager__NoStateHistoryFound();
    error StateManager__NoStateFoundAtBlock();
    error StateManager__StateIndexOutOfBounds(uint256 index);

    // state types
    enum StateType {
        IMMUTABLE,    // state that cannot be changed
        MONOTONIC     // state that can only increase
    }

    // state data structure
    struct State {
        bytes32 value;          // state value
        uint256 timestamp;      // timestamp when created
        uint256 blockNumber;    // block number when created
        uint256 nonce;         // sequence number
        StateType stateType;    // type of state
        bytes metadata;         // additional metadata
    }

    // emitted when a new state is committed
    event StateCommitted(
        address indexed user,
        bytes32 indexed value,
        uint256 timestamp,
        uint256 blockNumber,
        uint256 nonce,
        StateType stateType,
        bytes metadata
    );

    // commits a new state, returns old and new values
    function commitState(
        bytes32 value,
        StateType stateType,
        bytes calldata metadata
    ) external returns (uint256, uint256);

    // gets state at a specific block
    function getStateAtBlock(
        address user, 
        uint256 blockNumber
    ) external view returns (uint256);

    // gets latest state for a user
    function latest(address user) external view returns (uint256);

    // gets current nonce for a user
    function getCurrentNonce(address user) external view returns (uint256);

    // gets state at specific index
    function getState(
        address user, 
        uint256 index
    ) external view returns (State memory);

    // gets total number of states for a user
    function getStateCount(address user) external view returns (uint256);
}