// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@eigenlayer/contracts/libraries/BytesLib.sol";
import "./ICCTOTaskManager.sol";
import "@eigenlayer-middleware/src/ServiceManagerBase.sol";

/// @title CCTOServiceManager
/// @notice primary entry point for cross chain task oracle services
contract CCTOServiceManager is ServiceManagerBase {
    using BytesLib for bytes;

    // task manager contract
    ICCTOTaskManager public immutable cctoTaskManager;

    // only callable by task manager
    modifier onlyCCTOTaskManager() {
        require(
            msg.sender == address(cctoTaskManager),
            "not task manager"
        );
        _;
    }

    constructor(
        IAVSDirectory _avsDirectory,
        IRewardsCoordinator _rewardsCoordinator,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        ICCTOTaskManager _cctoTaskManager
    )
        ServiceManagerBase(_avsDirectory, _rewardsCoordinator, _registryCoordinator, _stakeRegistry)
    {
        cctoTaskManager = _cctoTaskManager;
    }

    // initialize contract with owner and rewards initiator
    function initialize(address initialOwner, address rewardsInitiator) external initializer {
        __ServiceManagerBase_init(initialOwner, rewardsInitiator);
    }

    // freeze operator on challenge resolution
    function freezeOperator(
        address operatorAddr
    ) external onlyCCTOTaskManager {
        // slasher.freezeOperator(operatorAddr);
    }
}
