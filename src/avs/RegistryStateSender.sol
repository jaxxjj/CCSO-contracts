// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAbridge} from "../interfaces/IAbridge.sol";
import {IRegistryCoordinator} from "../interfaces/IRegistryCoordinator.sol";
import {IStakeRegistry} from "../interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "../interfaces/IIndexRegistry.sol";
import {BitmapUtils} from "../libraries/BitmapUtils.sol";
import {Ownable2Step, Ownable} from "@openzeppelin-v5.0.0/contracts/access/Ownable2Step.sol";

contract RegistryStateSender is Ownable2Step {
    using BitmapUtils for uint256;

    IAbridge public immutable abridge;
    IRegistryCoordinator public immutable registryCoordinator;
    address public immutable receiver;

    // gas limit for cross chain message
    uint128 private constant EXECUTE_GAS_LIMIT = 500_000;

    error InsufficientFee();
    error WithdrawFailed();

    constructor(
        address _abridge,
        address _registryCoordinator,
        address _receiver,
        address _owner
    ) Ownable(_owner) {
        abridge = IAbridge(_abridge);
        registryCoordinator = IRegistryCoordinator(_registryCoordinator);
        receiver = _receiver;
    }

    // Withdraw unused bridge fees
    function withdraw(
        address to
    ) external onlyOwner {
        uint256 amount = address(this).balance;

        (bool success,) = to.call{value: amount}("");
        if (!success) revert WithdrawFailed();

        emit FundsWithdrawn(to, amount);
    }

    // sync all operators state
    function syncAllOperators() external payable {
        // get all operators data
        (address[] memory operators, uint192[] memory bitmaps, uint96[][] memory stakes) =
            _getAllOperatorsData();

        // encode data
        bytes memory operatorsData = abi.encode(operators, bitmaps, stakes);

        // estimate fee
        (, uint256 fee) = abridge.estimateFee(receiver, EXECUTE_GAS_LIMIT, operatorsData);
        if (msg.value < fee) revert InsufficientFee();

        // send through bridge
        abridge.send{value: msg.value}(receiver, EXECUTE_GAS_LIMIT, operatorsData);
    }

    // get all operators data
    function _getAllOperatorsData()
        internal
        view
        returns (address[] memory operators, uint192[] memory bitmaps, uint96[][] memory stakes)
    {
        // get registries
        IStakeRegistry stakeRegistry = registryCoordinator.stakeRegistry();
        IIndexRegistry indexRegistry = registryCoordinator.indexRegistry();
        uint8 quorumCount = registryCoordinator.quorumCount();

        // get current block number
        uint32 currentBlock = uint32(block.number);

        // get operators from first quorum
        bytes32[] memory operatorIds = indexRegistry.getOperatorListAtBlockNumber(0, currentBlock);

        // initialize arrays
        operators = new address[](operatorIds.length);
        bitmaps = new uint192[](operatorIds.length);
        stakes = new uint96[][](operatorIds.length);

        // collect data for each operator
        for (uint256 i = 0; i < operatorIds.length; i++) {
            bytes32 operatorId = operatorIds[i];
            operators[i] = indexRegistry.getOperatorFromId(operatorId);

            // get bitmap
            bitmaps[i] = registryCoordinator.getCurrentQuorumBitmap(operatorId);

            // get stakes for each quorum
            stakes[i] = new uint96[](quorumCount);
            for (uint8 j = 0; j < quorumCount; j++) {
                if (BitmapUtils.isSet(uint256(bitmaps[i]), j)) {
                    stakes[i][j] = stakeRegistry.getCurrentStake(operatorId, j);
                }
            }
        }
    }

    // Allow contract to receive ETH
    receive() external payable {}

    event FundsWithdrawn(address indexed to, uint256 amount);
}
