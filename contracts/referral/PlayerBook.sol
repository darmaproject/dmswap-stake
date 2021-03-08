pragma solidity ^0.5.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import "../library/NameFilter.sol";
import "../library/SafeERC20.sol";
import "../library/Governance.sol";
import "../interface/IPlayerBook.sol";

contract PlayerBook is Governance, IPlayerBook {
    using NameFilter for string;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // register pools       
    mapping (address => address) public _pools;
    address[] public _allpools;

    // (addr => pID) returns player id by address
    mapping (address => uint256) public _pIDxAddr;
    // (name => pID) returns player id by name      
    mapping (bytes32 => uint256) public _pIDxName;
    // (pID => data) player data     
    mapping (uint256 => Player) private _plyr;
    // (pID => name => bool) list of names a player owns.  (used so you can change your display name amoungst any name you own)
    mapping (uint256 => mapping (bytes32 => bool)) public _plyrNames;

    // the  of refrerrals
    mapping (address => uint256) public _totalReferReward;
    // total number of players
    uint256 public _pID;
    // total register name count
    uint256 public _totalRegisterCount = 0;

    // the direct refer's reward rate
    mapping (address => uint256) public _refer1RewardRate;
    // the second direct refer's reward rate
    mapping (address => uint256) public _refer2RewardRate;

    mapping (address => address) public _poolOwner;

    // base rate
    uint256 public _baseRate = 10000;

    // base price to register a name
    uint256 public _registrationBaseFee = 50 finney;
    // register fee count step
    uint256 public _registrationStep = 200;
    // add base price for one step
    uint256 public _stepFee = 50 finney;
    uint256 public _registrationFeeRatio = 100;

    bytes32 public _defaulRefer ="dmsw";

    address public _teamWallet = 0x6666666666666666666666666666666666666666;
    address payable public _ETHFeeWallet;
    address public factoryAddress;

    struct PlayerStats {
        uint256 amount;
        uint256 rreward;
        uint256 allReward;
    }

    struct Player {
        address addr;
        bytes32 name;
        uint8 nameCount;
        uint256 laff;
        mapping (address => PlayerStats) stats;
        uint256 lv1Count;
        uint256 lv2Count;
    }

    event eveClaim(uint256 pID, address addr, uint256 reward, uint256 balance );
    event eveBindRefer(uint256 pID, address addr, bytes32 name, uint256 affID, address affAddr, bytes32 affName);
    event eveDefaultPlayer(uint256 pID, address addr, bytes32 name);
    event eveNewName(uint256 pID, address addr, bytes32 name, uint256 affID, address affAddr, bytes32 affName, uint256 balance  );
    event eveSettle(uint256 pID, uint256 affID, uint256 aff_affID, uint256 affReward, uint256 aff_affReward, uint256 amount);
    event eveAddPool(address addr);
    event eveRemovePool(address addr);


    constructor()
    public
    {
        _ETHFeeWallet = tx.origin;
        factoryAddress = tx.origin;
        _pID = 0;
        addDefaultPlayer(_teamWallet,_defaulRefer);
    }

    /**
     * check address
     */
    modifier validAddress( address addr ) {
        require(addr != address(0x0));
        _;
    }

    /**
     * check pool
     */
    modifier isRegisteredPool(){
        require(_pools[msg.sender] != address(0) ,"invalid pool address!");
        _;
    }

    function setETHFeeAddress(address payable _feeAddress) public onlyGovernance {
        _ETHFeeWallet = _feeAddress;
    }

    function setFactoryAddress(address _factoryAddress) public onlyGovernance {
        factoryAddress = _factoryAddress;
    }

    function setRegistrationFeeRatio(uint256 registrationFeeRatio) public onlyGovernance{
        require(registrationFeeRatio>=0 && registrationFeeRatio<=100,"PlayerBook:INVALID PARAMETER!");
        _registrationFeeRatio = registrationFeeRatio;
    }

    /**
     * contract dego balances
     */
    function balances(address poolAddr)
    public
    view
    returns(uint256)
    {
        require(_pools[poolAddr] != address(0),"invalid pool address!");

        return (IERC20(_pools[poolAddr]).balanceOf(address(this)));
    }

    function withdrawTeamAssets(address poolAddr,address toAccount) external onlyGovernance returns (uint256 reward) {
        require(_pools[poolAddr] != address(0),"invalid pool address!");

        uint256 pid = _pIDxAddr[_teamWallet];
        reward = _plyr[pid].stats[poolAddr].rreward;

        require(reward > 0,"only have reward");

        _plyr[pid].stats[poolAddr].allReward = _plyr[pid].stats[poolAddr].allReward.add(reward);
        _plyr[pid].stats[poolAddr].rreward = 0;

        IERC20(_pools[poolAddr]).safeTransfer(toAccount, reward);

        emit eveClaim(_pIDxAddr[_teamWallet], toAccount, reward, balances(poolAddr));
    }

    // get register fee
    function seizeEth() external  {
        uint256 _currentBalance =  address(this).balance;
        _ETHFeeWallet.transfer(_currentBalance);
    }

    /**
     * revert invalid transfer action
     */
    function() external payable {
        revert();
    }

    function addPools(address[] calldata poolAddrs, address[] calldata rewardToken) external {
        require(poolAddrs.length == rewardToken.length, "PoolAddrs and rewardToken lengths mismatch");
        require(msg.sender == _governance, "not governance or factory");

        for (uint i = 0; i < poolAddrs.length; i++) {
            address poolAddr = poolAddrs[i];
            require( _pools[poolAddr] == address(0), "derp, that pool already been registered");

            _pools[poolAddr] = rewardToken[i];
            _refer1RewardRate[poolAddr] = 700;
            _refer2RewardRate[poolAddr] = 300;

            _poolOwner[poolAddr] = tx.origin;
            _allpools.push(poolAddr);

            emit eveAddPool(poolAddr);
        }
    }

    /**
     * registe a pool
     */
    function addPool(address poolAddr, address rewardToken)
    external
    {
        require(msg.sender == _governance || msg.sender == factoryAddress, "not governance or factory");
        require( _pools[poolAddr] == address(0), "derp, that pool already been registered");

        _pools[poolAddr] = rewardToken;
        _refer1RewardRate[poolAddr] = 700;
        _refer2RewardRate[poolAddr] = 300;

        _poolOwner[poolAddr] = tx.origin;
        _allpools.push(poolAddr);

        emit eveAddPool(poolAddr);
    }

    /**
     * remove a pool
     */
    function removePool(address poolAddr)
    onlyGovernance
    public
    {
        require( _pools[poolAddr] != address(0), "derp, that pool must be registered");

        _pools[poolAddr] = address(0);

        emit eveRemovePool(poolAddr);
    }

    /**
     * resolve the refer's reward from a player
     */
    function settleReward(address from, uint256 amount)
    isRegisteredPool()
    validAddress(from)
    external
    returns (uint256)
    {
        // set up our tx event data and determine if player is new or not
        _determinePID(from);

        uint256 pID = _pIDxAddr[from];
        uint256 affID = _plyr[pID].laff;

        if(affID <= 0 ){
            affID = _pIDxName[_defaulRefer];
            _plyr[pID].laff = affID;
        }

        if(amount <= 0){
            return 0;
        }

        uint256 fee = 0;

        address poolAddr = msg.sender;

        // father
        uint256 affReward = (amount.mul(_refer1RewardRate[poolAddr])).div(_baseRate);
        _plyr[affID].stats[poolAddr].rreward = _plyr[affID].stats[poolAddr].rreward.add(affReward);
        _totalReferReward[poolAddr] = _totalReferReward[poolAddr].add(affReward);
        fee = fee.add(affReward);

        // grandfather
        uint256 aff_affID = _plyr[affID].laff;
        uint256 aff_affReward = amount.mul(_refer2RewardRate[poolAddr]).div(_baseRate);
        if(aff_affID <= 0){
            aff_affID = _pIDxName[_defaulRefer];
        }
        _plyr[aff_affID].stats[poolAddr].rreward = _plyr[aff_affID].stats[poolAddr].rreward.add(aff_affReward);
        _totalReferReward[poolAddr] = _totalReferReward[poolAddr].add(aff_affReward);

        _plyr[pID].stats[poolAddr].amount = _plyr[pID].stats[poolAddr].amount.add( amount);

        fee = fee.add(aff_affReward);

        emit eveSettle( pID,affID,aff_affID,affReward,aff_affReward,amount);

        return fee;
    }

    /**
     * claim all of the refer reward.
     */
    function claim(address poolAddr)
    public
    {
        require(_pools[poolAddr] != address(0),"invalid pool address!");

        address addr = msg.sender;
        uint256 pid = _pIDxAddr[addr];
        uint256 reward = _plyr[pid].stats[poolAddr].rreward;

        require(reward > 0,"only have reward");

        //reset
        _plyr[pid].stats[poolAddr].allReward = _plyr[pid].stats[poolAddr].allReward.add(reward);
        _plyr[pid].stats[poolAddr].rreward = 0;

        //get reward
        IERC20(_pools[poolAddr]).safeTransfer(addr, reward);

        // fire event
        emit eveClaim(_pIDxAddr[addr], addr, reward, balances(poolAddr));
    }


    /**
     * check name string
     */
    function checkIfNameValid(string memory nameStr)
    public
    view
    returns(bool)
    {
        bytes32 name = nameStr.nameFilter();
        if (_pIDxName[name] == 0)
            return (true);
        else
            return (false);
    }

    /**
     * @dev add a default player
     */
    function addDefaultPlayer(address addr, bytes32 name)
    private
    {
        _pID++;

        _plyr[_pID].addr = addr;
        _plyr[_pID].name = name;
        _plyr[_pID].nameCount = 1;
        _pIDxAddr[addr] = _pID;
        _pIDxName[name] = _pID;
        _plyrNames[_pID][name] = true;

        //fire event
        emit eveDefaultPlayer(_pID,addr,name);
    }

    /**
     * @dev set refer reward rate
     */
    function setReferRewardRate(address poolAddr, uint256 refer1Rate, uint256 refer2Rate ) public
    {
        require(msg.sender == _governance || msg.sender == _poolOwner[poolAddr], "not governance or owner");

        require(_pools[poolAddr] != address(0),"invalid pool address!");

        _refer1RewardRate[poolAddr] = refer1Rate;
        _refer2RewardRate[poolAddr] = refer2Rate;
    }

    /**
     * @dev set registration step count
     */
    function setRegistrationStep(uint256 registrationStep) public
    onlyGovernance
    {
        _registrationStep = registrationStep;
    }

    /**
     * @dev set rewardtoken contract address
     */
    function setRewardContract(address poolAddr, address rewardToken)  public
    onlyGovernance{
        require(_pools[poolAddr] != address(0),"invalid pool address!");

        _pools[poolAddr] = rewardToken;
    }


    /**
     * @dev registers a name.  UI will always display the last name you registered.
     * but you will still own all previously registered names to use as affiliate
     * links.
     * - must pay a registration fee.
     * - name must be unique
     * - names will be converted to lowercase
     * - cannot be only numbers
     * - cannot start with 0x
     * - name must be at least 1 char
     * - max length of 32 characters long
     * - allowed characters: a-z, 0-9
     * -functionhash- 0x921dec21 (using ID for affiliate)
     * -functionhash- 0x3ddd4698 (using address for affiliate)
     * -functionhash- 0x685ffd83 (using name for affiliate)
     * @param nameString players desired name
     * @param affCode affiliate name of who refered you
     * (this might cost a lot of gas)
     */

    function registerNameXName(string memory nameString, string memory affCode)
    public
    payable
    {

        // make sure name fees paid
        uint regisFee = this.getRegistrationFee();
        require (msg.value >= regisFee, "umm.....  you have to pay the name fee");

        // filter name + condition checks
        bytes32 name = NameFilter.nameFilter(nameString);
        // if names already has been used
        require(_pIDxName[name] == 0, "sorry that names already taken");

        // set up address
        address addr = msg.sender;
        // set up our tx event data and determine if player is new or not
        _determinePID(addr);
        // fetch player id
        uint256 pID = _pIDxAddr[addr];
        // if names already has been used
        require(_plyrNames[pID][name] == false, "sorry that names already taken");

        // add name to player profile, registry, and name book
        _plyrNames[pID][name] = true;
        _pIDxName[name] = pID;
        _plyr[pID].name = name;
        _plyr[pID].nameCount++;

        _totalRegisterCount++;


        //try bind a refer
        if(_plyr[pID].laff == 0){

            bytes memory tempCode = bytes(affCode);
            bytes32 affName = 0x0;
            if (tempCode.length >= 0) {
                assembly {
                    affName := mload(add(tempCode, 32))
                }
            }

            _bindRefer(addr,affName);
        }
        uint256 affID = _plyr[pID].laff;

        // fire event
        emit eveNewName(pID, addr, name, affID, _plyr[affID].addr, _plyr[affID].name, regisFee );
    }

    /**
     * @dev bind a refer,if affcode invalid, use default refer
     */
    function bindRefer( address from, string calldata  affCode )
    isRegisteredPool()
    external
    returns (bool)
    {

        bytes memory tempCode = bytes(affCode);
        bytes32 affName = 0x0;
        if (tempCode.length >= 0) {
            assembly {
                affName := mload(add(tempCode, 32))
            }
        }

        return _bindRefer(from, affName);
    }


    /**
     * @dev bind a refer,if affcode invalid, use default refer
     */
    function _bindRefer( address from, bytes32  name )
    validAddress(msg.sender)
    validAddress(from)
    private
    returns (bool)
    {
        // set up our tx event data and determine if player is new or not
        _determinePID(from);

        // fetch player id
        uint256 pID = _pIDxAddr[from];
        if( _plyr[pID].laff != 0){
            return false;
        }

        if (_pIDxName[name] == 0){
            //unregister name
            name = _defaulRefer;
        }

        uint256 affID = _pIDxName[name];
        if( affID == pID){
            affID = _pIDxName[_defaulRefer];
        }

        _plyr[pID].laff = affID;

        //lvcount
        _plyr[affID].lv1Count++;
        uint256 aff_affID = _plyr[affID].laff;
        if(aff_affID != 0 ){
            _plyr[aff_affID].lv2Count++;
        }

        // fire event
        emit eveBindRefer(pID, from, name, affID, _plyr[affID].addr, _plyr[affID].name);

        return true;
    }

    //
    function _determinePID(address addr)
    private
    returns (bool)
    {
        if (_pIDxAddr[addr] == 0)
        {
            _pID++;
            _pIDxAddr[addr] = _pID;
            _plyr[_pID].addr = addr;

            // set the new player bool to true
            return (true);
        } else {
            return (false);
        }
    }

    function hasRefer(address from)
    isRegisteredPool()
    external
    returns(bool)
    {
        _determinePID(from);
        uint256 pID =  _pIDxAddr[from];
        return (_plyr[pID].laff > 0);
    }


    function getPlayerName(address from)
    external
    view
    returns (bytes32)
    {
        uint256 pID =  _pIDxAddr[from];
        if(_pID==0){
            return "";
        }
        return (_plyr[pID].name);
    }

    function getPlayerLaffName(address from)
    external
    view
    returns (bytes32)
    {
        uint256 pID =  _pIDxAddr[from];
        if(_pID==0){
            return "";
        }

        uint256 aID=_plyr[pID].laff;
        if( aID== 0){
            return "";
        }

        return (_plyr[aID].name);
    }

    function getPlayerInvterCount(address from)
    external view
    returns (uint256 lv1Count,uint256 lv2Count)
    {
        uint256 pID = _pIDxAddr[from];
        if(_pID==0){
            return (0,0);
        }
        lv1Count = _plyr[pID].lv1Count;
        lv2Count = _plyr[pID].lv2Count;
    }

    function getPlayerInfo(address from, address poolAddr)
    external
    view
    returns (uint256 rreward,uint256 allReward,uint256 lv1Count,uint256 lv2Count)
    {
        uint256 pID = _pIDxAddr[from];
        if(_pID==0){
            return (0,0,0,0);
        }
        rreward = _plyr[pID].stats[poolAddr].rreward;
        allReward = _plyr[pID].stats[poolAddr].allReward;
        lv1Count = _plyr[pID].lv1Count;
        lv2Count = _plyr[pID].lv2Count;
    }

    function getRewardPools(address account,uint256 pageindex,uint256 pagecount)
    external
    view
    returns (address[] memory,uint256)
    {
        if(pagecount == 0){
            pagecount = 10;
        }
        address[] memory pools;
        pools = new address[](pagecount);
        uint256 pID = _pIDxAddr[account];
        if(_pID==0){
            return (pools,0);
        }
        uint256 index = 0;
        uint256 count = 0;
        uint256 offset = pageindex.mul(pagecount);
        for (uint i = 0; i < _allpools.length; i++) {
            if(_pools[_allpools[i]] == address(0)){
                continue;
            }
            if(_plyr[pID].stats[_allpools[i]].rreward > 0 ||
            _plyr[pID].stats[_allpools[i]].allReward > 0){
                if(index >= offset ){
                    pools[count] = _allpools[i];
                    count++;
                    if(count >= pagecount){
                        break;
                    }
                }
                index++;
            }
        }
        return (pools, count);
    }

    function getTotalReferReward(address poolAddr)
    external
    view
    returns (uint256)
    {
        return(_totalReferReward[poolAddr]);
    }

    function getRegistrationFee()
    external
    view
    returns (uint256 registrationBaseFee)
    {

        if( _totalRegisterCount <_registrationStep || _registrationStep == 0){
            registrationBaseFee = _registrationBaseFee;
        }
        else{
            uint256 step = _totalRegisterCount.div(_registrationStep);
            registrationBaseFee = _registrationBaseFee.add(step.mul(_stepFee));
        }
        registrationBaseFee = registrationBaseFee.mul(_registrationFeeRatio).div(100);
    }
}
