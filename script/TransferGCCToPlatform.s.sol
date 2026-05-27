// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice One-shot transfer of GCC from the operator wallet to the AI.GG seller
///         address (`SUB2API_GCC_DEPOSIT_ADDRESS`). Uses SafeERC20 so the
///         script also tolerates ERC-20 tokens that return void or false
///         instead of reverting on failure.
contract TransferGCCToPlatform is Script {
    using SafeERC20 for IERC20;

    function run() external {
        IERC20 token = IERC20(vm.envAddress("GCC_TOKEN"));
        address recipient = vm.envAddress("SUB2API_GCC_DEPOSIT_ADDRESS");
        uint256 amount = vm.envUint("SUB2API_GCC_DEPOSIT_AMOUNT");

        vm.startBroadcast();
        token.safeTransfer(recipient, amount);
        vm.stopBroadcast();

        console2.log("GCC token:", address(token));
        console2.log("recipient:", recipient);
        console2.log("amount:", amount);
    }
}
