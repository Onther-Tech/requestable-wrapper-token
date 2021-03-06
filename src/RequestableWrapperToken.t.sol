pragma solidity ^0.4.24;

import "ds-test/test.sol";

import "./RequestableWrapperToken.sol";
import "ds-token/token.sol";

contract RootChain {
  RequestableWrapperToken wrapperToken;
  constructor(RequestableWrapperToken wrapperToken_) public {
      wrapperToken = wrapperToken_;
  }
  function doApplyInRootChain(
    bool isExit,
    uint256 requestId,
    address requestor,
    bytes32 trieKey,
    bytes trieValue) public {
    wrapperToken.applyRequestInRootChain(isExit, requestId, requestor, trieKey, trieValue);
  }
}

contract OwnerUser {
    function setOwner(DSAuth auth_, address newOwner_) public {
        auth_.setOwner(newOwner_);
    }
}

contract User{
  DSToken token;
  RequestableWrapperToken wrapperToken;
  constructor(DSToken token_, RequestableWrapperToken wrapperToken_) public {
    token = token_;
    wrapperToken = wrapperToken_;
    
  }
  function doApprove(address guy, uint wad) public returns (bool) {
    token.approve(guy, wad);
  }
  function doDeposit(uint amount) public returns (bool) {
    wrapperToken.deposit(amount);
  }
  function doWithdraw(uint amount) public returns (bool) {
    wrapperToken.withdraw(amount);
  }
}

contract TargetContract{}

contract RequestableWrapperTokenTest is DSTest {
    RequestableWrapperToken wrapperToken;
    DSToken token;
    RootChain rootchain;
    address NullAddress = address(0);
    OwnerUser ownerUser;
    User user;
    TargetContract target;

    function setUp() public {
        token = new DSToken('TEST');
        wrapperToken = new RequestableWrapperToken(true, 'WRAPPER', token);
        rootchain = new RootChain(wrapperToken);
        ownerUser = new OwnerUser();
        user = new User(token, wrapperToken);
        target = new TargetContract();
        wrapperToken.init(address(rootchain));
        assertTrue(wrapperToken.initialized());
    }

    function doApplyInChildChain(
      bool isExit,
      uint256 requestId,
      address requestor,
      bytes32 trieKey,
      bytes trieValue) public {
      wrapperToken.applyRequestInChildChain(isExit, requestId, requestor, trieKey, trieValue);
    }

    function toBytesUint(uint256 x) public returns (bytes b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function toBytesAddress(address x) public returns (bytes b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function testDepositAndWithdraw() public {
      token.mint(100);
      assertEq(token.balanceOf(this), 100);

      token.approve(wrapperToken);
      wrapperToken.deposit(100);
      assertEq(token.balanceOf(user), 0);
      assertEq(wrapperToken.balanceOf(this), 100);

      wrapperToken.withdraw(100);
      assertEq(wrapperToken.balanceOf(this), 0);
      assertEq(token.balanceOf(this), 100);

      // in the case of different account from deployer of wrapper contract.
      // in this case, different account is user and deployer is this.
      // deposit
      token.transfer(user, 100);
      user.doApprove(wrapperToken, 100);
      user.doDeposit(100);
      assertEq(token.balanceOf(user), 0);
      assertEq(wrapperToken.balanceOf(user), 100);

      // withdraw
      user.doWithdraw(100);
      assertEq(token.balanceOf(user), 100);
      assertEq(wrapperToken.balanceOf(user), 0);
    }

    function testApprove() public {
      // approve all amounts of wrapper token
      wrapperToken.approve(target);
      assertEq(wrapperToken.allowance(this, target), uint(-1));
      
      // approve 100 amounts of wrapper token
      wrapperToken.approve(target, 100);
      assertEq(wrapperToken.allowance(this, target), 100);
    }

    function testApplyOwner() public {
        bool isExit = true;
        uint requestId = 0;
        bytes32 trieKey = 0x1;
        bytes memory trieValue;

        // initial
        assertEq(token.owner(), this);

        // exit in root chain
        trieValue = toBytesAddress(ownerUser);
        rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
        assertEq(wrapperToken.owner(), address(ownerUser));

        // reset owner
        ownerUser.setOwner(wrapperToken, this);
        assertEq(wrapperToken.owner(), this);

        // enter in root chain
        isExit = false;
        requestId += 1;
        trieValue = toBytesAddress(this);
        rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
        assertEq(wrapperToken.owner(), this);

        // exit in child chain
        isExit = true;
        requestId += 1;
        trieValue = toBytesAddress(this);
        wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);
        assertEq(wrapperToken.owner(), this);

        // enter in child chain
        isExit = false;
        requestId += 1;
        trieValue = toBytesAddress(ownerUser);
        wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);
        assertEq(wrapperToken.owner(), address(ownerUser));

        // reset owner
        ownerUser.setOwner(wrapperToken, this);
        assertEq(wrapperToken.owner(), this);
    }

    function testApplyStopped() public {
        bool stopped = true;
        bool notStopped = false;

        bool isExit = true;
        uint requestId = 0;
        bytes32 trieKey = 0x2;
        bytes memory trieValue;

        // initial
        assertTrue(wrapperToken.stopped() == notStopped);

        // exit in root chain
        isExit = true;
        trieValue = toBytesUint(0x1);
        rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
        assertTrue(wrapperToken.stopped() == stopped);

        // exit in child chain
        isExit = true;
        requestId += 1;
        trieValue = toBytesUint(0x0);
        wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);
        assertTrue(wrapperToken.stopped() == stopped);

        // enter in root chain
        isExit = false;
        requestId += 1;
        trieValue = toBytesUint(0x0);
        rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
        assertTrue(wrapperToken.stopped() == stopped);

        // enter in child chain
        isExit = false;
        requestId += 1;
        trieValue = toBytesUint(0x0);
        wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);
        assertTrue(wrapperToken.stopped() == notStopped);
    }

    function testApplyBalance() public {
      // init
      token.mint(100);
      token.approve(wrapperToken);
      wrapperToken.deposit(100);

      // enter in root chain
      bool isExit = false;
      uint requestId = 0;
      bytes32 trieKey = wrapperToken.getBalanceTrieKey(this);
      bytes memory trieValue;

      trieValue = toBytesUint(10);
      rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
      assertEq(wrapperToken.balanceOf(this), 90);

      // enter in child chain
      isExit = false;
      trieValue = toBytesUint(10);
      requestId += 1;
      wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);

      assertEq(wrapperToken.balanceOf(this), 100);

      // exit in child chain
      isExit = true;
      trieValue = toBytesUint(10);
      requestId += 1;
      wrapperToken.applyRequestInChildChain(isExit, requestId, this, trieKey, trieValue);
      assertEq(wrapperToken.balanceOf(this), 90);

      // exit in root chain
      isExit = true;
      requestId += 1;
      trieValue = toBytesUint(10);
      rootchain.doApplyInRootChain(isExit, requestId, this, trieKey, trieValue);
      assertEq(wrapperToken.balanceOf(this), 100);
    }

   
}
