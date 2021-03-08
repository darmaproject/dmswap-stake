pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";


import "../interface/IERC20.sol";
import "../interface/IPool.sol";
import "./SafeERC20.sol";
import "./Governance.sol";
import "../interface/IPlayerBook.sol";
import "../interface/IPowerStrategy.sol";
import "./SegmentPowerStrategy.sol";


contract LPTokenWrapper is IPool,Governance {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public _lpToken;

    address public _playerBook = address(0xD6C7bE3582F120aC08CFd947b3964a83F614482D);

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 private _totalPower;
    mapping(address => uint256) private _powerBalances;
    
    address public _powerStrategy = address(0x0);
    address public powerStrategy = address(0x0);

    constructor(address lpToken_) public {
        require(lpToken_ != address(0), 'LPTokenWrapper::constructor: lpToken_ is empty');
        _lpToken = IERC20(lpToken_);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function enablePowerStragegy()  public  onlyGovernance{
        if( powerStrategy == address(0x0)){
            powerStrategy = address(new SegmentPowerStrategy());
        }
        _powerStrategy = powerStrategy;
    }

    function disablePowerStragegy()  public  onlyGovernance{
        _powerStrategy = address(0x0);
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function balanceOfPower(address account) public view returns (uint256) {
        return _powerBalances[account];
    }

    function totalPower() public view returns (uint256) {
        return _totalPower;
    }


    function stake(uint256 amount, string memory affCode) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);

        if( _powerStrategy != address(0x0)){ 
            _totalPower = _totalPower.sub(_powerBalances[msg.sender]);
            IPowerStrategy(_powerStrategy).lpIn(msg.sender, amount);

            _powerBalances[msg.sender] = IPowerStrategy(_powerStrategy).getPower(msg.sender);
            _totalPower = _totalPower.add(_powerBalances[msg.sender]);
        }else{
            _totalPower = _totalSupply;
            _powerBalances[msg.sender] = _balances[msg.sender];
        }

        _lpToken.safeTransferFrom(msg.sender, address(this), amount);


        if (!IPlayerBook(_playerBook).hasRefer(msg.sender)) {
            IPlayerBook(_playerBook).bindRefer(msg.sender, affCode);
        }

        
    }

    function withdraw(uint256 amount) public {
        require(amount > 0, "amount > 0");

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        
        if( _powerStrategy != address(0x0)){ 
            _totalPower = _totalPower.sub(_powerBalances[msg.sender]);
            IPowerStrategy(_powerStrategy).lpOut(msg.sender, amount);
            _powerBalances[msg.sender] = IPowerStrategy(_powerStrategy).getPower(msg.sender);
            _totalPower = _totalPower.add(_powerBalances[msg.sender]);

        }else{
            _totalPower = _totalSupply;
            _powerBalances[msg.sender] = _balances[msg.sender];
        }
        _lpToken.safeTransfer( msg.sender, amount);
    }


    function setPlayerBook(address playerbook) public onlyGovernance{
        _playerBook = playerbook;
    }
}