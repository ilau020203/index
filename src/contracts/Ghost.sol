// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '../interfaces/IGhost.sol';

contract Ghost is IGhost {
  function boo() external pure returns (string memory) {
    return 'Boo!';
  }
}
