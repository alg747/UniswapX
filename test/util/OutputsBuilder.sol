// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {OutputToken} from "../../src/base/ReactorStructs.sol";
import {DutchOutput} from "../../src/reactors/DutchLimitOrderReactor.sol";

library OutputsBuilder {
    function single(address token, uint256 amount, address recipient) internal pure returns (OutputToken[] memory) {
        OutputToken[] memory result = new OutputToken[](1);
        result[0] = OutputToken(token, amount, recipient, false);
        return result;
    }

    function multiple(address token, uint256[] memory amounts, address recipient)
        internal
        pure
        returns (OutputToken[] memory)
    {
        OutputToken[] memory result = new OutputToken[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            result[i] = OutputToken(token, amounts[i], recipient, false);
        }
        return result;
    }

    function multiple(address[] memory tokens, uint256[] memory amounts, address[] memory recipients)
        internal
        pure
        returns (OutputToken[] memory)
    {
        OutputToken[] memory result = new OutputToken[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            result[i] = OutputToken(tokens[i], amounts[i], recipients[i], false);
        }
        return result;
    }

    function singleDutch(address token, uint256 startAmount, uint256 endAmount, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        DutchOutput[] memory result = new DutchOutput[](1);
        result[0] = DutchOutput(token, startAmount, endAmount, recipient, false);
        return result;
    }

    // Returns array of dutch outputs. <startAmounts> and <endAmounts> have same length.
    /// TODO: Support multiple tokens + recipients
    function multipleDutch(address token, uint256[] memory startAmounts, uint256[] memory endAmounts, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        DutchOutput[] memory result = new DutchOutput[](startAmounts.length);
        for (uint256 i = 0; i < startAmounts.length; i++) {
            result[i] = DutchOutput(token, startAmounts[i], endAmounts[i], recipient, false);
        }
        return result;
    }
}
