// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IVaporDEXFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
