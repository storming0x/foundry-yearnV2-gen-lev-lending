// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import "ds-test/test.sol";

contract ExtendedDSTest is DSTest {
    // solhint-disable-next-line
    function assertNeq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    // @dev checks whether @a is within certain percentage of @b
    // @a actual value
    // @b expected value
    // solhint-disable-next-line
    function assertRelApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta
    ) internal virtual {
        uint256 delta = a > b ? a - b : b - a;
        uint256 maxRelDelta = b / maxPercentDelta;

        if (delta > maxRelDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            emit log_named_uint(" Max Delta", maxRelDelta);
            emit log_named_uint("     Delta", delta);
            fail();
        }
    }
}
