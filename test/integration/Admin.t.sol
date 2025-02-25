// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import "test/BaseTest.sol";

contract AdminTest is BaseTest {
    function setUp() public override {
        super.setUp();
        pauseAdmin.addPauser(address(this));
    }

    function testDeployment() public {
        // values set correctly
        assertEq(address(root.escrow()), address(escrow));
        assertEq(root.paused(), false);

        // permissions set correctly
        assertEq(root.wards(address(delayedAdmin)), 1);
        assertEq(root.wards(address(pauseAdmin)), 1);
        assertEq(pauseAdmin.wards(address(delayedAdmin)), 1);
        assertEq(aggregator.wards(address(delayedAdmin)), 1);
    }

    //------ PauseAdmin tests ------//
    function testPause() public {
        pauseAdmin.removePauser(address(this));
        vm.expectRevert("PauseAdmin/not-authorized-to-pause");
        pauseAdmin.pause();

        pauseAdmin.addPauser(address(this));
        pauseAdmin.pause();
        assertEq(root.paused(), true);

        delayedAdmin.unpause();
        assertEq(root.paused(), false);
    }

    function testPauseAuth(address user) public {
        vm.assume(user != address(this));
        vm.expectRevert("PauseAdmin/not-authorized-to-pause");
        vm.prank(user);
        pauseAdmin.pause();
    }

    function testOutgoingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        vm.expectRevert("Gateway/paused");
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
    }

    function testIncomingTransferWhilePausedFails(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);

        pauseAdmin.pause();
        vm.expectRevert("Gateway/paused");
        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
    }

    function testUnpausingResumesFunctionality(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        uint128 currency,
        bytes32 sender,
        address recipient,
        uint128 amount
    ) public {
        decimals = uint8(bound(decimals, 1, 18));
        vm.assume(amount > 0);
        vm.assume(currency != 0);
        vm.assume(recipient != address(investmentManager.escrow()));
        vm.assume(recipient != address(0));

        ERC20 erc20 = _newErc20(tokenName, tokenSymbol, decimals);
        vm.assume(recipient != address(erc20));
        centrifugeChain.addCurrency(currency, address(erc20));

        // First, an outgoing transfer must take place which has funds currency of the currency moved to
        // the escrow account, from which funds are moved from into the recipient on an incoming transfer.
        erc20.approve(address(poolManager), type(uint256).max);
        erc20.mint(address(this), amount);
        pauseAdmin.pause();
        delayedAdmin.unpause();
        poolManager.transfer(address(erc20), bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), amount);

        centrifugeChain.incomingTransfer(currency, sender, bytes32(bytes20(recipient)), amount);
        assertEq(erc20.balanceOf(address(poolManager.escrow())), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    //------ Delayed admin tests ------///
    function testDelayedAdminPause() public {
        delayedAdmin.pause();
        assertEq(root.paused(), true);

        delayedAdmin.unpause();
        assertEq(root.paused(), false);
    }

    function testDelayedAdminPauseAuth(address user) public {
        vm.assume(user != address(this));
        vm.expectRevert("Auth/not-authorized");
        vm.prank(user);
        delayedAdmin.pause();
    }

    function testTimelockWorks() public {
        address spell = vm.addr(1);
        delayedAdmin.scheduleRely(spell);
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(spell);
        assertEq(root.wards(spell), 1);
    }

    function testTimelockFailsBefore48hours() public {
        address spell = vm.addr(1);
        delayedAdmin.scheduleRely(spell);
        vm.warp(block.timestamp + delay - 1 hours);
        vm.expectRevert("Root/target-not-ready");
        root.executeScheduledRely(spell);
    }

    function testCancellingScheduleWorks() public {
        address spell = vm.addr(1);
        vm.expectRevert("Root/target-not-scheduled");
        root.cancelRely(spell);

        delayedAdmin.scheduleRely(spell);
        assertEq(root.schedule(spell), block.timestamp + delay);
        delayedAdmin.cancelRely(spell);
        assertEq(root.schedule(spell), 0);
        vm.warp(block.timestamp + delay + 1 hours);
        vm.expectRevert("Root/target-not-scheduled");
        root.executeScheduledRely(spell);
    }

    function testUnauthorizedCancelFails() public {
        address spell = vm.addr(1);
        delayedAdmin.scheduleRely(spell);
        vm.expectRevert("Auth/not-authorized");
        vm.prank(spell);
        delayedAdmin.cancelRely(spell);
    }

    function testAddPauser() public {
        address newPauser = vm.addr(0xABCDE);

        address badActor = vm.addr(0xBAD);
        vm.prank(badActor);
        vm.expectRevert("Auth/not-authorized");
        delayedAdmin.addPauser(badActor);

        delayedAdmin.addPauser(newPauser);
        assertEq(pauseAdmin.pausers(newPauser), 1);
    }

    function testRemovePauser() public {
        address oldPauser = vm.addr(0xABCDE);

        address badActor = vm.addr(0xBAD);
        vm.prank(badActor);
        vm.expectRevert("Auth/not-authorized");
        delayedAdmin.removePauser(badActor);

        delayedAdmin.removePauser(oldPauser);
        assertEq(pauseAdmin.pausers(oldPauser), 0);
    }

    function testIncomingScheduleUpgradeMessage() public {
        address spell = vm.addr(1);
        centrifugeChain.incomingScheduleUpgrade(spell);
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(spell);
        assertEq(root.wards(spell), 1);
    }

    function testIncomingCancelUpgradeMessage() public {
        address spell = vm.addr(1);
        centrifugeChain.incomingScheduleUpgrade(spell);
        assertEq(root.schedule(spell), block.timestamp + delay);
        centrifugeChain.incomingCancelUpgrade(spell);
        assertEq(root.schedule(spell), 0);
        vm.warp(block.timestamp + delay + 1 hours);
        vm.expectRevert("Root/target-not-scheduled");
        root.executeScheduledRely(spell);
    }

    //------ Updating delay tests ------///
    function testUpdatingDelay() public {
        delayedAdmin.scheduleRely(address(this));
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(address(this));

        vm.expectRevert("Root/delay-too-long");
        root.file("delay", 5 weeks);

        root.file("delay", 2 hours);
        delayedAdmin.scheduleRely(address(this));
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert("Root/target-not-ready");
        root.executeScheduledRely(address(this));
    }

    function testInvalidFile() public {
        vm.expectRevert("Root/file-unrecognized-param");
        root.file("not-delay", 1);
    }

    //------ rely/denyContract tests ------///
    function testRelyDenyContract() public {
        delayedAdmin.scheduleRely(address(this));
        vm.warp(block.timestamp + delay + 1 hours);
        root.executeScheduledRely(address(this));

        assertEq(investmentManager.wards(address(this)), 1);
        root.denyContract(address(investmentManager), address(this));
        assertEq(investmentManager.wards(address(this)), 0);

        root.relyContract(address(investmentManager), address(this));
        assertEq(investmentManager.wards(address(this)), 1);
    }
}
