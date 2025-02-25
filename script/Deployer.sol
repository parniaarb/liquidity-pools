// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Root} from "src/Root.sol";
import {RouterAggregator} from "src/gateway/routers/RouterAggregator.sol";
import {Gateway, InvestmentManagerLike} from "src/gateway/Gateway.sol";
import {InvestmentManager} from "src/InvestmentManager.sol";
import {PoolManager} from "src/PoolManager.sol";
import {Escrow} from "src/Escrow.sol";
import {UserEscrow} from "src/UserEscrow.sol";
import {PauseAdmin} from "src/admins/PauseAdmin.sol";
import {DelayedAdmin} from "src/admins/DelayedAdmin.sol";
import {LiquidityPoolFactory} from "src/factories/LiquidityPoolFactory.sol";
import {RestrictionManagerFactory} from "src/factories/RestrictionManagerFactory.sol";
import {TrancheTokenFactory} from "src/factories/TrancheTokenFactory.sol";
import "forge-std/Script.sol";

interface RouterLike {
    function file(bytes32 what, address data) external;
}

interface AuthLike {
    function rely(address who) external;
    function deny(address who) external;
}

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;

    address admin;
    address[] pausers;
    address[] routers;

    Root public root;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    UserEscrow public userEscrow;
    PauseAdmin public pauseAdmin;
    DelayedAdmin public delayedAdmin;
    Gateway public gateway;
    RouterAggregator public aggregator;
    address public liquidityPoolFactory;
    address public restrictionManagerFactory;
    address public trancheTokenFactory;

    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );
        escrow = new Escrow{salt: salt}(deployer);
        userEscrow = new UserEscrow();
        root = new Root{salt: salt}(address(escrow), delay, deployer);

        liquidityPoolFactory = address(new LiquidityPoolFactory(address(root)));
        restrictionManagerFactory = address(new RestrictionManagerFactory(address(root)));
        trancheTokenFactory = address(new TrancheTokenFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(escrow), address(userEscrow));
        poolManager =
            new PoolManager(address(escrow), liquidityPoolFactory, restrictionManagerFactory, trancheTokenFactory);

        AuthLike(liquidityPoolFactory).rely(address(poolManager));
        AuthLike(trancheTokenFactory).rely(address(poolManager));
        AuthLike(restrictionManagerFactory).rely(address(poolManager));

        AuthLike(liquidityPoolFactory).rely(address(root));
        AuthLike(trancheTokenFactory).rely(address(root));
        AuthLike(restrictionManagerFactory).rely(address(root));

        gateway = new Gateway(address(root), address(investmentManager), address(poolManager));
        aggregator = new RouterAggregator(address(gateway));

        pauseAdmin = new PauseAdmin(address(root));
        delayedAdmin = new DelayedAdmin(address(root), address(pauseAdmin), address(aggregator));
    }

    function wire(address router) public {
        routers.push(router);

        // Wire aggregator
        aggregator.file("routers", routers);
        gateway.file("aggregator", address(aggregator));
        gateway.rely(address(aggregator));

        // Wire admins
        pauseAdmin.rely(address(delayedAdmin));
        root.rely(address(pauseAdmin));
        root.rely(address(delayedAdmin));
        root.rely(address(gateway));
        aggregator.rely(address(delayedAdmin));

        // Wire gateway
        investmentManager.file("poolManager", address(poolManager));
        poolManager.file("investmentManager", address(investmentManager));
        investmentManager.file("gateway", address(gateway));
        poolManager.file("gateway", address(gateway));
        investmentManager.rely(address(root));
        investmentManager.rely(address(gateway));
        investmentManager.rely(address(liquidityPoolFactory));
        poolManager.rely(address(root));
        poolManager.rely(address(gateway));
        gateway.rely(address(root));
        aggregator.rely(address(root));
        AuthLike(router).rely(address(root));
        AuthLike(address(escrow)).rely(address(root));
        AuthLike(address(userEscrow)).rely(address(root));
        AuthLike(address(userEscrow)).rely(address(investmentManager));
        AuthLike(address(escrow)).rely(address(poolManager));
    }

    function giveAdminAccess() public {
        delayedAdmin.rely(address(admin));

        for (uint256 i = 0; i < pausers.length; i++) {
            pauseAdmin.addPauser(pausers[i]);
        }
    }

    function removeDeployerAccess(address router, address deployer) public {
        AuthLike(router).deny(deployer);
        AuthLike(liquidityPoolFactory).deny(deployer);
        AuthLike(trancheTokenFactory).deny(deployer);
        AuthLike(restrictionManagerFactory).deny(deployer);
        root.deny(deployer);
        investmentManager.deny(deployer);
        poolManager.deny(deployer);
        escrow.deny(deployer);
        userEscrow.deny(deployer);
        gateway.deny(deployer);
        aggregator.deny(deployer);
        pauseAdmin.deny(deployer);
        delayedAdmin.deny(deployer);
    }
}
