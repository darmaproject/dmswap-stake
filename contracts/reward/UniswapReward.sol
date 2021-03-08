pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interface/IERC20.sol";
import "../interface/IPlayerBook.sol";

import "../library/LPTokenWrapper.sol";
import "../library/SafeERC20.sol";



contract RewardsDistributionRecipient {
    address public rewardsDistribution;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }
}


interface IUniswapV2ERC20 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}


contract UniswapReward is LPTokenWrapper,RewardsDistributionRecipient{
    using SafeERC20 for IERC20;

    IERC20 public _rewardsToken;
    address public _teamWallet = 0x1F91db93e06ffeb06c942BB6A0b2756Ad6Aaa5FC;
    address public _rewardPool = 0x25655b50d6f9Ff59cA145F3E6976E954bE17B177;

    uint256 public constant DURATION = 7 days;

    uint256 public _initReward;
    uint256 public _periodFinish = 0;
    uint256 public _rewardRate = 0;
    uint256 public _lastUpdateTime;
    uint256 public _rewardPerTokenStored;

    uint256 public _teamRewardRate = 500;
    uint256 public _poolRewardRate = 1000;
    uint256 public _baseRate = 10000;
    uint256 public _punishTime = 3 days;

    mapping(address => uint256) public _userRewardPerTokenPaid;
    mapping(address => uint256) public _rewards;
    mapping(address => uint256) public _lastStakedTime;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);


    modifier updateReward(address account) {
        _rewardPerTokenStored = rewardPerToken();
        _lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = _rewardPerTokenStored;
        }
        _;
    }

    constructor(
        address rewardsDistribution_,
        address token_,
        address lpToken_
    ) LPTokenWrapper(lpToken_) public {
        require(token_ != address(0), 'UniswapReward::constructor: _token is empty');

        _rewardsToken = IERC20(token_);
        rewardsDistribution = rewardsDistribution_;
    }

    /* Fee collection for any other token */
    function seize(IERC20 token, uint256 amount) external onlyGovernance{
        require(token != _rewardsToken, "reward");
        require(token != _lpToken, "stake");
        token.safeTransfer(_governance, amount);
    }

    function setTeamRewardRate( uint256 teamRewardRate ) public onlyGovernance{
        _teamRewardRate = teamRewardRate;
    }

    function setPoolRewardRate( uint256  poolRewardRate ) public onlyGovernance{
        _poolRewardRate = poolRewardRate;
    }

    function setWithDrawPunishTime( uint256  punishTime ) public onlyGovernance{
        _punishTime = punishTime;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, _periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalPower() == 0) {
            return _rewardPerTokenStored;
        }
        return
            _rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(_lastUpdateTime)
                    .mul(_rewardRate)
                    .mul(1e18)
                    .div(totalPower())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOfPower(account)
                .mul(rewardPerToken().sub(_userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(_rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount, string memory affCode)
        public
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        super.stake(amount, affCode);

        _lastStakedTime[msg.sender] = now;

        emit Staked(msg.sender, amount);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stakeWithPermit(uint256 amount, string memory affCode, uint deadline, uint8 v, bytes32 r, bytes32 s)
        public
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");

        // permit
        IUniswapV2ERC20(address(_lpToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        super.stake(amount, affCode);

        _lastStakedTime[msg.sender] = now;

        emit Staked(msg.sender, amount);
    }



    function withdraw(uint256 amount)
    public
    updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            _rewards[msg.sender] = 0;
            uint256 fee = IPlayerBook(_playerBook).settleReward(msg.sender, reward);
            if(fee > 0){
                _rewardsToken.safeTransfer(_playerBook, fee);
            }
            
            uint256 teamReward = reward.mul(_teamRewardRate).div(_baseRate);
            if(teamReward>0){
                _rewardsToken.safeTransfer(_teamWallet, teamReward);
            }
            uint256 leftReward = reward.sub(fee).sub(teamReward);
            uint256 poolReward = 0;

            //withdraw time check

            if(now  < (_lastStakedTime[msg.sender] + _punishTime) ){
                poolReward = leftReward.mul(_poolRewardRate).div(_baseRate);
            }
            if(poolReward>0){
                _rewardsToken.safeTransfer(_rewardPool, poolReward);
                leftReward = leftReward.sub(poolReward);
            }

            if(leftReward>0){
                _rewardsToken.safeTransfer(msg.sender, leftReward );
            }
      
            emit RewardPaid(msg.sender, leftReward);
        }
    }

    //for extra reward
    function notifyRewardAmount(uint256 reward)
        external
        onlyRewardsDistribution
        updateReward(address(0))
    {
        if (block.timestamp >= _periodFinish) {
            _rewardRate = reward.div(DURATION);
        } else {
            uint256 remaining = _periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(_rewardRate);
            _rewardRate = reward.add(leftover).div(DURATION);
        }
        _lastUpdateTime = block.timestamp;
        _periodFinish = block.timestamp.add(DURATION);
        emit RewardAdded(reward);
    }
}
