// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAbridgeMessageHandler} from "../interfaces/IAbridge.sol";
import {IRegistryCoordinator} from "../interfaces/IRegistryCoordinator.sol";
import {IAbridge} from "../interfaces/IAbridge.sol";
import {Ownable2Step, Ownable} from "@openzeppelin-v5.0.0/contracts/access/Ownable2Step.sol";

contract RegistryStateReceiver is IAbridgeMessageHandler, Ownable2Step {
    IRegistryCoordinator public immutable registryCoordinator;
    IAbridge public immutable abridge;
    address public immutable sender;

    // operator states
    mapping(address => uint192) public operatorBitmaps;
    mapping(address => mapping(uint8 => uint96)) public operatorStakes;

    error InvalidSender();
    error UpdateRouteFailed();

    constructor(
        address _registryCoordinator,
        address _abridge,
        address _sender,
        address _owner
    ) Ownable(_owner) {
        registryCoordinator = IRegistryCoordinator(_registryCoordinator);
        abridge = IAbridge(_abridge);
        sender = _sender;

        // Enable route from sender
        abridge.updateRoute(sender, true);
    }

    // update route settings
    function updateRoute(
        bool allowed
    ) external onlyOwner {
        abridge.updateRoute(sender, allowed);
    }

    function handleMessage(
        address from,
        bytes calldata message,
        bytes32 /*guid*/
    ) external returns (bytes4) {
        if (from != sender) revert InvalidSender();

        // decode operators data
        (address[] memory operators, uint192[] memory bitmaps, uint96[][] memory stakes) =
            abi.decode(message, (address[], uint192[], uint96[][]));

        // update states
        for (uint256 i = 0; i < operators.length; i++) {
            address operator = operators[i];
            operatorBitmaps[operator] = bitmaps[i];

            // update stakes for each quorum
            for (uint8 j = 0; j < stakes[i].length; j++) {
                operatorStakes[operator][j] = stakes[i][j];
            }

            emit OperatorStateUpdated(operator, bitmaps[i]);
        }

        return IAbridgeMessageHandler.handleMessage.selector;
    }

    // Get operator's complete state
    function getOperatorState(
        address operator,
        uint8 quorumCount
    ) external view returns (uint192 bitmap, uint96[] memory stakes) {
        bitmap = operatorBitmaps[operator];
        stakes = new uint96[](quorumCount);

        for (uint8 i = 0; i < quorumCount; i++) {
            stakes[i] = operatorStakes[operator][i];
        }
    }

    event OperatorStateUpdated(address indexed operator, uint192 bitmap);
}
