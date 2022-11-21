// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {InputToken, OutputToken, OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {IPSFees} from "../../src/base/IPSFees.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockIPSFees} from "../util/mock/MockIPSFees.sol";

contract IPSFeesTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using OrderInfoLib for OrderInfo;

    uint256 constant ONE = 10 ** 18;
    address constant INTERFACE_FEE_RECIPIENT = address(10);
    address constant PROTOCOL_FEE_RECIPIENT = address(11);
    address constant RECIPIENT = address(12);
    // 50/50 split
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockIPSFees fees;

    function setUp() public {
        fees = new MockIPSFees(PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
    }

    function testInvalidFee() public {
        vm.expectRevert(IPSFees.InvalidFee.selector);
        new MockIPSFees(10001, PROTOCOL_FEE_RECIPIENT);
    }

    function testTakeFees() public {
        ResolvedOrder memory order = createOrder(ONE);
        assertEq(order.outputs[order.outputs.length - 1].recipient, INTERFACE_FEE_RECIPIENT);
        ResolvedOrder memory newOrder = fees.takeFees(order);

        assertEq(fees.feesOwed(address(tokenOut), address(0)), ONE / 2);
        assertEq(fees.feesOwed(address(tokenOut), INTERFACE_FEE_RECIPIENT), ONE / 2);
        assertEq(newOrder.outputs[newOrder.outputs.length - 1].recipient, address(fees));
    }

    function testTakeFees(uint128 amount) public {
        fees.takeFees(createOrder(amount));

        assertEq(fees.feesOwed(address(tokenOut), address(0)), amount / 2);
        assertEq(fees.feesOwed(address(tokenOut), INTERFACE_FEE_RECIPIENT), amount - amount / 2);
    }

    function testTakeSeveralFees() public {
        fees.takeFees(createOrder(ONE));
        fees.takeFees(createOrder(ONE * 2));
        fees.takeFees(createOrder(ONE * 5));
        fees.takeFees(createOrder(ONE * 2));
        assertEq(fees.feesOwed(address(tokenOut), address(0)), ONE * 10 / 2);
        assertEq(fees.feesOwed(address(tokenOut), INTERFACE_FEE_RECIPIENT), ONE * 10 / 2);
    }

    function testNoFeeOutput() public {
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(0)),
            sig: hex"00",
            hash: bytes32(0)
        });

        ResolvedOrder memory newOrder = fees.takeFees(order);
        // doesn't modify the one output
        assertEq(newOrder.outputs.length, 1);
        assertEq(newOrder.outputs[0].recipient, address(0));
        assertEq(newOrder.outputs[0].amount, ONE);
    }

    function testClaimFees() public {
        fees.takeFees(createOrder(ONE));
        deal(address(tokenOut), address(fees), ONE);

        uint256 preBalance = tokenOut.balanceOf(address(PROTOCOL_FEE_RECIPIENT));
        vm.prank(PROTOCOL_FEE_RECIPIENT);
        fees.claimFees(address(tokenOut));
        assertEq(tokenOut.balanceOf(address(PROTOCOL_FEE_RECIPIENT)), preBalance + ONE / 2);
        assertEq(fees.feesOwed(address(tokenOut), address(0)), 0);

        preBalance = tokenOut.balanceOf(INTERFACE_FEE_RECIPIENT);
        vm.prank(INTERFACE_FEE_RECIPIENT);
        fees.claimFees(address(tokenOut));
        assertEq(tokenOut.balanceOf(INTERFACE_FEE_RECIPIENT), preBalance + ONE / 2);
        assertEq(fees.feesOwed(address(tokenOut), INTERFACE_FEE_RECIPIENT), 0);
    }

    function testSetProtocolFeeRecipient() public {
        assertEq(fees.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
        vm.prank(PROTOCOL_FEE_RECIPIENT);
        fees.setProtocolFeeRecipient(address(0));
        assertEq(fees.protocolFeeRecipient(), address(0));
    }

    function testOnlyCurrentFeeRecipientCanSet() public {
        assertEq(fees.protocolFeeRecipient(), PROTOCOL_FEE_RECIPIENT);
        vm.prank(address(0));
        vm.expectRevert(IPSFees.UnauthorizedFeeRecipient.selector);
        fees.setProtocolFeeRecipient(address(0));
    }

    function testOldFeeRecipientCannotClaim() public {
        fees.takeFees(createOrder(ONE));
        deal(address(tokenOut), address(fees), ONE);

        assertEq(tokenOut.balanceOf(address(PROTOCOL_FEE_RECIPIENT)), 0);
        vm.startPrank(PROTOCOL_FEE_RECIPIENT);
        fees.setProtocolFeeRecipient(address(0));
        fees.claimFees(address(tokenOut));
        assertEq(tokenOut.balanceOf(address(PROTOCOL_FEE_RECIPIENT)), 0);
    }

    function createOrder(uint256 amount) private view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken(address(tokenOut), ONE, RECIPIENT);
        outputs[1] = OutputToken(address(tokenOut), amount, INTERFACE_FEE_RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }
}
