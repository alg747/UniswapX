// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SettlementEvents} from "../base/SettlementEvents.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {
    ResolvedOrder,
    SettlementInfo,
    ActiveSettlement,
    OutputToken,
    SettlementStatus
} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain settler logic for settling off-chain signed orders
/// using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => ActiveSettlement) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /// @inheritdoc IOrderSettler
    function initiateSettlement(SignedOrder calldata order, address targetChainFiller) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order);
        _initiateSettlements(resolvedOrders, targetChainFiller);
    }

    function _initiateSettlements(ResolvedOrder[] memory orders, address targetChainFiller) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                order.validate(msg.sender);
                collectEscrowTokens(order);

                if (settlements[order.hash].deadline != 0) revert SettlementAlreadyInitiated(order.hash);

                settlements[order.hash] = ActiveSettlement({
                    status: SettlementStatus.Pending,
                    offerer: order.info.offerer,
                    originChainFiller: msg.sender,
                    targetChainFiller: targetChainFiller,
                    settlementOracle: order.info.settlementOracle,
                    deadline: block.timestamp + order.info.settlementPeriod,
                    input: order.input,
                    collateral: order.collateral,
                    outputs: order.outputs
                });

                emit InitiateSettlement(
                    order.hash,
                    order.info.offerer,
                    msg.sender,
                    targetChainFiller,
                    order.info.settlementOracle,
                    block.timestamp + order.info.settlementPeriod
                    );
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function cancelSettlement(bytes32 orderId) external override {
        ActiveSettlement storage settlement = settlements[orderId];
        if (settlement.deadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.status == SettlementStatus.Pending && settlement.deadline < block.timestamp) {
            settlement.status = SettlementStatus.Cancelled;

            // transfer tokens and collateral back to offerer
            ERC20(settlement.input.token).safeTransfer(settlement.offerer, settlement.input.amount);
            ERC20(settlement.collateral.token).safeTransfer(settlement.offerer, settlement.input.amount);
            emit CancelSettlement(orderId);
        } else {
            revert UnableToCancel(orderId);
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeSettlement(bytes32 orderId) external override {
        ActiveSettlement memory settlement = settlements[orderId];
        if (settlement.deadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.status == SettlementStatus.Pending) {
            OutputToken[] memory filledOutputs = ISettlementOracle(settlement.settlementOracle).getSettlementInfo(
                orderId, settlement.targetChainFiller
            );

            if (filledOutputs.length != settlement.outputs.length) revert OutputsLengthMismatch(orderId);

            // validate outputs
            for (uint16 i; i < filledOutputs.length; i++) {
                OutputToken memory expectedOutput = settlement.outputs[i];
                OutputToken memory receivedOutput = filledOutputs[i];
                if (expectedOutput.recipient != receivedOutput.recipient) revert InvalidRecipient(orderId, i);
                if (expectedOutput.token != receivedOutput.token) revert InvalidToken(orderId, i);
                if (expectedOutput.amount < receivedOutput.amount) revert InvalidAmount(orderId, i);
                if (expectedOutput.chainId != receivedOutput.chainId) revert InvalidChain(orderId, i);
            }

            // compensate filler
            settlements[orderId].status = SettlementStatus.Filled;
            ERC20(settlement.input.token).safeTransfer(settlement.originChainFiller, settlement.input.amount);
            ERC20(settlement.collateral.token).safeTransfer(settlement.originChainFiller, settlement.input.amount);
            emit FinalizeSettlement(orderId);
        } else {
            revert SettlementAlreadyCompleted(orderId, settlement.status);
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Collects swapper input tokens as well as collateral tokens of filler to escrow them until settlement is
    /// finalized or cancelled
    /// @param order The encoded order to transfer tokens for
    function collectEscrowTokens(ResolvedOrder memory order) internal virtual;
}
