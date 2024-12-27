// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../interfaces/IStateManager.sol";

/// @title StateManager
/// @notice manages and stores states, supporting immutable and monotonic state types
contract StateManager is IStateManager {

    // storage mappings
    mapping(address => State[]) private userStates;
    
    // commit new state
    function commitState(
        bytes32 value,
        StateType stateType,
        bytes calldata metadata
    ) external returns (uint256, uint256) {
        if (stateType != StateType.IMMUTABLE && stateType != StateType.MONOTONIC) {
            revert StateManager__InvalidStateType();
        }
        
        State[] storage states = userStates[msg.sender];
        
        if (stateType == StateType.MONOTONIC && states.length > 0) {
            if (uint256(value) <= uint256(states[states.length - 1].value)) {
                revert StateManager__ValueNotMonotonic();
            }
        }
        
        uint256 currentNonce = states.length > 0 ? 
            states[states.length - 1].nonce + 1 : 0;

        State memory newState = State({
            value: value,
            timestamp: block.timestamp,
            blockNumber: block.number,
            nonce: currentNonce,
            stateType: stateType,
            metadata: metadata
        });
        
        uint256 oldValue = states.length > 0 ? uint256(states[states.length - 1].value) : 0;
        states.push(newState);
        
        emit StateCommitted(
            msg.sender,
            value,
            newState.timestamp,
            newState.blockNumber,
            currentNonce,
            stateType,
            metadata
        );

        return (oldValue, uint256(value));
    }

    // get state changes between blocks
    function getStateChangesBetween(
        address user,
        uint256 fromBlock,
        uint256 toBlock
    ) external view returns (State[] memory) {
        if (fromBlock >= toBlock) {
            revert StateManager__InvalidBlockRange();
        }
        if (toBlock >= block.number) {
            revert StateManager__BlockNotYetMined(toBlock);
        }

        State[] storage states = userStates[user];
        uint256 count = 0;
        
        // count states in range
        for (uint256 i = 0; i < states.length; i++) {
            if (states[i].blockNumber >= fromBlock && 
                states[i].blockNumber <= toBlock) {
                count++;
            }
        }
        
        State[] memory changes = new State[](count);
        uint256 index = 0;
        
        // collect states in range
        for (uint256 i = 0; i < states.length && index < count; i++) {
            if (states[i].blockNumber >= fromBlock && 
                states[i].blockNumber <= toBlock) {
                changes[index] = states[i];
                index++;
            }
        }
        
        return changes;
    }

    // get latest state value
    function latest(address user) public view returns (uint256) {
        State[] storage states = userStates[user];
        return states.length == 0 ? 0 : uint256(states[states.length - 1].value);
    }

    // get state at specific block
    function getStateAtBlock(
        address user, 
        uint256 blockNumber
    ) external view returns (uint256) {
        if (blockNumber >= block.number) {
            revert StateManager__BlockNotYetMined(blockNumber);
        }

        State[] storage states = userStates[user];
        uint256 high = states.length;
        uint256 low = 0;

        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (states[mid].blockNumber > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high == 0 ? 0 : uint256(states[high - 1].value);
    }

    // get full state by block number
    function getStateByBlockNumber(
        address user,
        uint256 blockNumber
    ) public view returns (State memory) {
        if (blockNumber >= block.number) {
            revert StateManager__BlockNotYetMined(blockNumber);
        }
        
        State[] storage states = userStates[user];
        if (states.length == 0) {
            revert StateManager__NoStateHistoryFound();
        }

        uint256 index = _findStateIndex(states, blockNumber);
        if (index >= states.length) {
            revert StateManager__NoStateFoundAtBlock();
        }

        return states[index];
    }

    // binary search for state index
    function _findStateIndex(
        State[] storage states,
        uint256 targetBlock
    ) private view returns (uint256) {
        uint256 left = 0;
        uint256 right = states.length;

        while (left < right) {
            uint256 mid = Math.average(left, right);
            if (states[mid].blockNumber > targetBlock) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }

        return right == 0 ? 0 : right - 1;
    }

    // query functions
    function getCurrentNonce(address user) external view returns (uint256) {
        State[] storage states = userStates[user];
        return states.length == 0 ? 0 : states[states.length - 1].nonce;
    }

    function getState(
        address user, 
        uint256 index
    ) external view returns (State memory) {
        if (index >= userStates[user].length) {
            revert StateManager__StateIndexOutOfBounds(index);
        }
        return userStates[user][index];
    }

    function getStateCount(address user) external view returns (uint256) {
        return userStates[user].length;
    }

    // get state snapshots for given blocks
    function getStateSnapshots(
        address user,
        uint256[] calldata blockNumbers
    ) external view returns (State[] memory) {
        State[] memory snapshots = new State[](blockNumbers.length);
        
        for (uint256 i = 0; i < blockNumbers.length; i++) {
            snapshots[i] = getStateByBlockNumber(user, blockNumbers[i]);
        }
        
        return snapshots;
    }

    // get latest N states for a user
    function getLatestStates(
        address user,
        uint256 count
    ) external view returns (State[] memory) {
        State[] storage states = userStates[user];
        uint256 resultCount = Math.min(count, states.length);
        State[] memory result = new State[](resultCount);
        
        for (uint256 i = 0; i < resultCount; i++) {
            result[i] = states[states.length - resultCount + i];
        }
        
        return result;
    }

    // get states after timestamp
    function getStatesAfterTimestamp(
        address user,
        uint256 timestamp
    ) external view returns (State[] memory) {
        State[] storage states = userStates[user];
        uint256 count = 0;
        
        // count matching states
        for (uint256 i = 0; i < states.length; i++) {
            if (states[i].timestamp > timestamp) {
                count++;
            }
        }
        
        State[] memory result = new State[](count);
        uint256 index = 0;
        
        // collect matching states
        for (uint256 i = 0; i < states.length && index < count; i++) {
            if (states[i].timestamp > timestamp) {
                result[index] = states[i];
                index++;
            }
        }
        
        return result;
    }
}