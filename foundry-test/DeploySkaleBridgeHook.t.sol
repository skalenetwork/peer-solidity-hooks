pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { DeploySkaleBridgeHook } from "../script/DeploySkaleBridgeHook.s.sol";
import { MockDepositBoxERC20 } from "../contracts/mocks/MockDepositBoxERC20.sol";
import { MockMessageProxyForMainnet } from "../contracts/mocks/MockMessageProxyForMainnet.sol";
import { SkaleBridgeHook } from "../contracts/SkaleBridgeHook.sol";

contract DeploySkaleBridgeHookTest is Test {
    string constant SCHAIN = "test-chain";

    function test_deployScript_setsCorrectState() public {
        MockDepositBoxERC20 depositBox = new MockDepositBoxERC20();
        MockMessageProxyForMainnet proxy = new MockMessageProxyForMainnet();
        proxy.setConnectedChain(SCHAIN, true);

        address orchestrator = makeAddr("orchestrator");

        vm.setEnv("ORCHESTRATOR", vm.toString(orchestrator));
        vm.setEnv("DEPOSIT_BOX", vm.toString(address(depositBox)));
        vm.setEnv("MESSAGE_PROXY", vm.toString(address(proxy)));
        vm.setEnv("SKALE_CHAIN_NAME", SCHAIN);

        DeploySkaleBridgeHook script = new DeploySkaleBridgeHook();
        SkaleBridgeHook hook = script.run();

        assertEq(hook.ORCHESTRATOR(), orchestrator);
        assertEq(address(hook.DEPOSIT_BOX()), address(depositBox));
        assertEq(hook.skaleChainName(), SCHAIN);
        assertEq(hook.owner(), DEFAULT_SENDER); // vm.startBroadcast() without args uses DEFAULT_SENDER
    }

    function test_deployScript_transfersOwnership_whenOwnerEnvSet() public {
        MockDepositBoxERC20 depositBox = new MockDepositBoxERC20();
        MockMessageProxyForMainnet proxy = new MockMessageProxyForMainnet();
        proxy.setConnectedChain(SCHAIN, true);

        address orchestrator = makeAddr("orchestrator");
        address newOwner = makeAddr("newOwner");

        vm.setEnv("ORCHESTRATOR", vm.toString(orchestrator));
        vm.setEnv("DEPOSIT_BOX", vm.toString(address(depositBox)));
        vm.setEnv("MESSAGE_PROXY", vm.toString(address(proxy)));
        vm.setEnv("SKALE_CHAIN_NAME", SCHAIN);
        vm.setEnv("OWNER", vm.toString(newOwner));

        DeploySkaleBridgeHook script = new DeploySkaleBridgeHook();
        SkaleBridgeHook hook = script.run();

        // transferOwnership in Ownable2Step is a two-step process:
        // the deployer remains owner until the pending owner calls acceptOwnership()
        assertEq(hook.owner(), DEFAULT_SENDER);
        assertEq(hook.pendingOwner(), newOwner);
    }
}
