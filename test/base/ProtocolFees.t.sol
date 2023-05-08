// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Test} from "forge-std/Test.sol";
import {InputToken, OutputToken, OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockProtocolFees} from "../util/mock/MockProtocolFees.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {MockFeeControllerDuplicates} from "../util/mock/MockFeeControllerDuplicates.sol";

contract ProtocolFeesTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using ResolvedOrderLib for OrderInfo;

    address constant INTERFACE_FEE_RECIPIENT = address(10);
    address constant PROTOCOL_FEE_OWNER = address(11);
    address constant RECIPIENT = address(12);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockProtocolFees fees;
    MockFeeController feeController;

    function setUp() public {
        fees = new MockProtocolFees(PROTOCOL_FEE_OWNER);
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        feeController = new MockFeeController(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(feeController));
    }

    function testSetFeeController() public {
        assertEq(address(fees.feeController()), address(feeController));
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(2));
        assertEq(address(fees.feeController()), address(2));
    }

    function testSetFeeControllerOnlyOwner() public {
        assertEq(address(fees.feeController()), address(feeController));
        vm.prank(address(1));
        vm.expectRevert("UNAUTHORIZED");
        fees.setProtocolFeeController(address(2));
        assertEq(address(fees.feeController()), address(feeController));
    }

    function testTakeFeesNoFees() public {
        ResolvedOrder memory order = createOrder(1 ether, false);

        assertEq(order.outputs.length, 1);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 1);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
    }

    function testTakeFees() public {
        ResolvedOrder memory order = createOrder(1 ether, false);
        uint256 feeBps = 3;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        assertEq(order.outputs.length, 1);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 2);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
        assertEq(afterFees.outputs[1].token, order.outputs[0].token);
        assertEq(afterFees.outputs[1].amount, order.outputs[0].amount * feeBps / 10000);
        assertEq(afterFees.outputs[1].recipient, RECIPIENT);
    }

    function testTakeFeesFuzzOutputs(uint128 inputAmount, uint128[] memory outputAmounts, uint256 feeBps) public {
        vm.assume(feeBps <= 5);
        OutputToken[] memory outputs = new OutputToken[](outputAmounts.length);
        for (uint256 i = 0; i < outputAmounts.length; i++) {
            outputs[i] = OutputToken(address(tokenOut), outputAmounts[i], RECIPIENT);
        }
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        for (uint256 i = 0; i < outputs.length; i++) {
            feeController.setFee(address(tokenIn), address(outputs[i].token), feeBps);
        }

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertGe(afterFees.outputs.length, outputs.length);

        for (uint256 i = 0; i < outputAmounts.length; i++) {
            address tokenAddress = order.outputs[i].token;
            uint256 baseAmount = order.outputs[i].amount;

            uint256 extraOutputs = afterFees.outputs.length - outputAmounts.length;
            for (uint256 j = 0; j < extraOutputs; j++) {
                OutputToken memory output = afterFees.outputs[outputAmounts.length + j];
                if (output.token == tokenAddress) {
                    assertGe(output.amount, baseAmount * feeBps / 10000);
                }
            }
        }
    }

    function testTakeFeesWithInterfaceFee() public {
        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 3;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        assertEq(order.outputs.length, 2);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 3);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
        assertEq(afterFees.outputs[1].token, order.outputs[1].token);
        assertEq(afterFees.outputs[1].amount, order.outputs[1].amount);
        assertEq(afterFees.outputs[1].recipient, order.outputs[1].recipient);
        assertEq(afterFees.outputs[2].token, order.outputs[1].token);
        assertEq(afterFees.outputs[2].amount, (order.outputs[1].amount + order.outputs[1].amount) * feeBps / 10000);
        assertEq(afterFees.outputs[2].recipient, RECIPIENT);
    }

    function testTakeFeesTooMuch() public {
        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 10;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        vm.expectRevert(ProtocolFees.FeeTooLarge.selector);
        fees.takeFees(order);
    }

    function testTakeFeesDuplicate() public {
        MockFeeControllerDuplicates controller = new MockFeeControllerDuplicates(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(controller));

        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 10;
        controller.setFee(address(tokenIn), address(tokenOut), feeBps);

        vm.expectRevert(ProtocolFees.DuplicateFeeOutput.selector);
        fees.takeFees(order);
    }

    function createOrder(uint256 amount, bool isEthOutput) private view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](1);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }

    function createOrderWithInterfaceFee(uint256 amount, bool isEthOutput)
        private
        view
        returns (ResolvedOrder memory)
    {
        OutputToken[] memory outputs = new OutputToken[](2);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, RECIPIENT);
        outputs[1] = OutputToken(outputToken, amount, INTERFACE_FEE_RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }
}
