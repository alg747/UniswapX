// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, SettlementStatus} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order settlers. These contracts collect escrow tokens from the swapper and filler
/// and consult an oracle to determine whether the cross-chain fill is completed within the valid fill timeframe. OrderSettlers
/// will vary by order type (i.e. dutch limit order) but one OrderSettler may receive orders for any target chain since
/// cross-chain SettlementOracles are outsourced to oracles of the swappers choice.
interface IOrderSettler {
    /// @notice Thrown when trying to perform an action on a pending settlement that's already been completed
    /// @param orderId The order hash to identify the order
    /// @param currentStatus The actual status of the settlement (either Filled or Cancelled)
    error SettlementAlreadyCompleted(bytes32 orderId, SettlementStatus currentStatus);

    /// @notice Thrown when trying to cancen an order that cannot be cancelled because deadline has not passed, or the
    /// order is already completed
    /// @param orderId The order hash to identify the order
    error UnableToCancel(bytes32 orderId);

    /// @notice Thrown when validating a settlement fill but the recipient does not match the expected recipient
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidRecipient(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the token does not match the expected token
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidToken(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the amount does not match the expected amount
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidAmount(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the chainId does not match the expected chainId
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidChain(bytes32 orderId, uint16 outputIndex);

    /// @notice Initiate a single order settlement using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    /// @param crossChainFiller Address reserved as the valid address to initiate the fill on the cross-chain settlementFiller
    function initiateSettlement(SignedOrder calldata order, address crossChainFiller) external;

    /// @notice Finalize a settlement by first: confirming the cross-chain fill has happened and second: transferring
    /// input tokens and collateral to the filler
    /// @param orderId The order hash that identifies the order settlement to finalize
    function finalizeSettlement(bytes32 orderId) external;

    /// @notice Cancels a settmentlent that was never filled after the settlement deadline. Input and collateral tokens
    /// are returned to swapper
    /// @param orderId The order hash that identifies the order settlement to cancel
    function cancelSettlement(bytes32 orderId) external;
}
