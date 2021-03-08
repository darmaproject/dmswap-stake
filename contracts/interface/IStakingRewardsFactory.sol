pragma solidity ^0.5.16;


interface IStakingRewardsFactory {
    function deploy(
        address stakingToken_,
        address lpToken_,
        uint256 initReward_,
        uint256 emissionRatio_,
        uint256 machineUnit_,
        uint256 lossRate_,
        uint256 rewardDuration_,
        uint256 finishDuration_
    ) external returns (address);
}
