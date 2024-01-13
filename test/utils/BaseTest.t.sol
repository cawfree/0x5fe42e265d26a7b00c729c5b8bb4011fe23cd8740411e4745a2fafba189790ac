// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

contract BaseTest is Test {

    address internal constant _ALICE = address(0x1);
    address internal constant _BOB = address(0x2);
    address internal constant _DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {}

}
