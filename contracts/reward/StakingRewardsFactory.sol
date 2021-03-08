/**
 *Submitted for verification at Etherscan.io on 2020-09-16
*/

pragma solidity ^0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./UniswapReward.sol";
import "../library/Governance.sol";

interface IMinterV2ERC20 {
    function mint(address dst, uint rawAmount) external;
}

contract StakingRewardsFactory is Governance {
    using SafeMath for uint;
    // immutables
    address public rewardsToken;
    address public govRewardAccount;
    address public devRewardAccount;
    uint public stakingRateGenesis=95400;
    uint public stakingRateTotal=950000;//95%Percent * 10000
    uint public stakingRewardsGenesis;

    // the staking tokens for which the rewards contract has been deployed
    address[] public stakingTokens;

    uint public rewardRateTotal=0;

    // info about rewards for a particular staking token
    struct StakingRewardsInfo {
        address stakingRewards;
        uint rewardRate;
    }

    // rewards info by staking token
    mapping(address => StakingRewardsInfo) public stakingRewardsInfoByStakingToken;

    constructor(
        address _rewardsToken,
        address _govRewardAccount,
        address _devRewardAccount,
        uint _stakingRewardsGenesis
    ) Governance() public {
        require(_stakingRewardsGenesis >= block.timestamp, 'StakingRewardsFactory::constructor: genesis too soon');

        rewardsToken = _rewardsToken;
        govRewardAccount = _govRewardAccount;
        devRewardAccount = _devRewardAccount;
        stakingRewardsGenesis = _stakingRewardsGenesis;
    }

    ///// permissioned functions

    // deploy a staking reward contract for the staking token, and store the reward amount
    // the reward will be distributed to the staking reward contract no sooner than the genesis
    function deploy(address[] memory _stakingTokens, uint[] memory _rewardRates) public onlyGovernance {
        require(_stakingTokens.length == _rewardRates.length, "stakingTokens and rewardRates lengths mismatch");

        for (uint i = 0; i < _rewardRates.length; i++) {
            require(_stakingTokens[i] != address(0), "StakingRewardsFactory::deploy: stakingToken empty");

            StakingRewardsInfo storage  info = stakingRewardsInfoByStakingToken[_stakingTokens[i]];

            rewardRateTotal = rewardRateTotal.sub(info.rewardRate).add(_rewardRates[i]);
            info.rewardRate = _rewardRates[i];

            if(info.stakingRewards == address(0)){
                info.stakingRewards = address(new UniswapReward(
                    /*rewardsDistribution_=*/ address(this),
                    /*token_=*/     rewardsToken,
                    /*lpToken_=*/     _stakingTokens[i]
                    ));
                stakingTokens.push(_stakingTokens[i]);
            }
        }
    }

    function setStakingRate(address stakingToken,uint rewardRate) public onlyGovernance {
        StakingRewardsInfo storage info = stakingRewardsInfoByStakingToken[stakingToken];
        require(info.stakingRewards != address(0), 'StakingRewardsFactory::setStakingEnabled: not deployed');

        rewardRateTotal = rewardRateTotal.sub(info.rewardRate).add(rewardRate);
        info.rewardRate = rewardRate;
    }

    function rewardTotalToken() public view returns (uint256) {
        if (stakingRateGenesis >= stakingRateTotal) {
            return stakingRateTotal.mul(100).mul(1e18);
        }
        return stakingRateGenesis.mul(100).mul(1e18);
    }

    ///// permissionless functions

    // call notifyRewardAmount for all staking tokens.
    function notifyRewardAmounts() public {
        require(stakingTokens.length > 0, 'StakingRewardsFactory::notifyRewardAmounts: called before any deploys');
        require(block.timestamp >= stakingRewardsGenesis, 'StakingRewardsFactory::notifyRewardAmounts: reward not start');
        require(stakingRateTotal > 0, 'StakingRewardsFactory::notifyRewardAmounts: reward is over');

        if(stakingRateGenesis >= stakingRateTotal){
            stakingRateGenesis = stakingRateTotal;
        }
        uint _totalRewardAmount = rewardTotalToken();// equal 100_000_000 * 95400 / 10000 / 100

        stakingRewardsGenesis = stakingRewardsGenesis + 7 days;
        stakingRateTotal = stakingRateTotal.sub(stakingRateGenesis);
        if(stakingRateGenesis > 57400){//next stop rate 5.7400%
            stakingRateGenesis = stakingRateGenesis.mul(9300).div(10000);//next reward rate equal stakingRateGenesis * (1-7%)
        }else if(stakingRateGenesis > 20023){
            stakingRateGenesis = 20023;//next reward rate equal 2.0023%
        }else{
            stakingRateGenesis = stakingRateGenesis.mul(9487).div(10000);//next reward rate equal stakingRateGenesis * (1-5.13%)
        }

        _mint(_totalRewardAmount);

        uint _govFundAmount = _totalRewardAmount.mul(5).div(100);// 5%
        uint _devFundAmount = _totalRewardAmount.mul(15).div(100);// 15%
        _reserveRewards(govRewardAccount,_govFundAmount);
        _reserveRewards(devRewardAccount,_devFundAmount);

        uint _poolRewardAmount = _totalRewardAmount.sub(_govFundAmount).sub(_devFundAmount); // 80%
        _notifyPoolRewardAmounts(_poolRewardAmount);
    }

    function _notifyPoolRewardAmounts(uint _poolRewardAmount) private {
        uint _surplusRewardAmount = _poolRewardAmount;
        uint _rewardAmount = 0;
        address farmAddr;

        for (uint i = 0; i < stakingTokens.length; i++) {
            StakingRewardsInfo memory info = stakingRewardsInfoByStakingToken[stakingTokens[i]];
            if(info.rewardRate <= 0){
                continue;
            }
            if(stakingTokens[i] == rewardsToken){
                farmAddr = info.stakingRewards;
                continue;
            }
            _rewardAmount = _poolRewardAmount.mul(info.rewardRate).div(rewardRateTotal);
            if(_rewardAmount >= _surplusRewardAmount){
                _rewardAmount = _surplusRewardAmount;
            }
            _surplusRewardAmount = _surplusRewardAmount.sub(_rewardAmount);
            _notifyRewardAmount(info.stakingRewards,_rewardAmount);
        }
        _surplusRewardAmount = IERC20(rewardsToken).balanceOf(address(this));
        if(_surplusRewardAmount > 0 && farmAddr != address(0)){
            _notifyRewardAmount(farmAddr,_surplusRewardAmount);
        }
    }


    // notify reward amount for an individual staking token.
    // this is a fallback in case the notifyRewardAmounts costs too much gas to call for all contracts
    function _notifyRewardAmount(address _stakingToken,uint _rewardAmount) private {
        require(_stakingToken != address(0), 'StakingRewardsFactory::notifyRewardAmount: not deployed');

        if (_rewardAmount > 0) {
            require(
                IERC20(rewardsToken).transfer(_stakingToken, _rewardAmount),
                'StakingRewardsFactory::notifyRewardAmount: transfer failed'
            );
            UniswapReward(_stakingToken).notifyRewardAmount(_rewardAmount);
        }
    }

    function _reserveRewards(address _account,uint _rawRewardsAmount) private {
        require(_account != address(0), 'StakingRewardsFactory::_reserveRewards: not deployed');

        require(
            IERC20(rewardsToken).transfer(_account, _rawRewardsAmount),
            'StakingRewardsFactory::_reserveRewards: transfer failed'
        );
    }

    function _mint(uint _mintAmount) private {
        require(_mintAmount > 0, 'StakingRewardsFactory::_mint: mintAmount is zero');

        IMinterV2ERC20(rewardsToken).mint(address(this), _mintAmount);
    }
}