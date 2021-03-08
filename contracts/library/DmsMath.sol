pragma solidity ^0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

library DmsMath {
    using SafeMath for uint256;

    function pow(uint256 x,uint256 n,uint256 min) public pure returns (uint256 rate) {
        if(x <= min){
            return min;
        }
        if(n <= 0){
            rate = 10000;
        }else if(n == 1){
            rate = x;
        }else if(n == 2){
            rate = x.mul(x).div(10000);
        }else{
            uint s = pow(x,n/2,min);
            s = s.mul(s).div(10000);
            if( n%2 != 0){
                s = s.mul(x).div(10000);
            }
            rate = s;
        }
        return rate <= min ? min : rate;
    }
}