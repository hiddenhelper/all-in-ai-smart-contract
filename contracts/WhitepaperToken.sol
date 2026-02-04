// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "owner=0");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "owner=0");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract Pausable is Ownable {
    bool public paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor(address initialOwner) Ownable(initialOwner) {}

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    function pause() external onlyOwner {
        require(!paused, "paused");
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        require(paused, "not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }
}

contract ReentrancyGuard {
    uint256 private _status = 1;

    modifier nonReentrant() {
        require(_status == 1, "reentrant");
        _status = 2;
        _;
        _status = 1;
    }
}

contract ERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;

    uint256 internal _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory tokenName, string memory tokenSymbol) {
        name = tokenName;
        symbol = tokenSymbol;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "allowance");
        _approve(from, msg.sender, currentAllowance - amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "zero addr");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "zero addr");
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "zero addr");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "balance");
        _balances[from] = fromBalance - amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0) && spender != address(0), "zero addr");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

contract WhitepaperToken is ERC20, Pausable {
    uint256 public immutable cap;
    mapping(address => bool) public isMinter;

    event MinterUpdated(address indexed account, bool allowed);

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 maxSupply,
        address[] memory initialRecipients,
        uint256[] memory initialAmounts,
        address ownerAddress
    ) ERC20(tokenName, tokenSymbol) Pausable(ownerAddress) {
        require(maxSupply > 0, "cap=0");
        require(initialRecipients.length == initialAmounts.length, "len");
        cap = maxSupply;
        isMinter[ownerAddress] = true;
        emit MinterUpdated(ownerAddress, true);
        uint256 total;
        for (uint256 i = 0; i < initialRecipients.length; i++) {
            _mint(initialRecipients[i], initialAmounts[i]);
            total += initialAmounts[i];
        }
        require(total <= cap, "cap exceeded");
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        isMinter[account] = allowed;
        emit MinterUpdated(account, allowed);
    }

    function mint(address to, uint256 amount) external whenNotPaused {
        require(isMinter[msg.sender], "not minter");
        require(totalMinted() + amount <= cap, "cap exceeded");
        _mint(to, amount);
    }

    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
    }

    function transfer(address to, uint256 amount) external override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }

    function totalMinted() public view returns (uint256) {
        return _totalSupply;
    }
}

contract TokenVesting is ReentrancyGuard {
    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable startTimestamp;
    uint64 public immutable cliffDuration;
    uint64 public immutable vestingDuration;
    uint256 public released;

    event Released(uint256 amount);

    constructor(
        IERC20 tokenAddress,
        address beneficiaryAddress,
        uint64 startTime,
        uint64 cliffSeconds,
        uint64 durationSeconds
    ) {
        require(address(tokenAddress) != address(0), "token=0");
        require(beneficiaryAddress != address(0), "beneficiary=0");
        require(durationSeconds > 0, "duration=0");
        token = tokenAddress;
        beneficiary = beneficiaryAddress;
        startTimestamp = startTime;
        cliffDuration = cliffSeconds;
        vestingDuration = durationSeconds;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    function release() external nonReentrant {
        uint256 amount = releasable();
        require(amount > 0, "none");
        released += amount;
        require(token.transfer(beneficiary, amount), "transfer failed");
        emit Released(amount);
    }

    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 totalBalance = token.balanceOf(address(this)) + released;
        if (timestamp < startTimestamp + cliffDuration) {
            return 0;
        }
        if (timestamp >= startTimestamp + vestingDuration) {
            return totalBalance;
        }
        uint256 elapsed = timestamp - startTimestamp;
        return (totalBalance * elapsed) / vestingDuration;
    }
}

contract StakingPool is Ownable, ReentrancyGuard {
    IERC20 public immutable stakingToken;

    uint256 public totalStaked;
    uint256 public rewardRate;
    uint256 public rewardsDuration;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardConfigured(uint256 reward, uint256 duration);

    constructor(IERC20 tokenAddress, address ownerAddress) Ownable(ownerAddress) {
        require(address(tokenAddress) != address(0), "token=0");
        stakingToken = tokenAddress;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return (balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "amount=0");
        totalStaked += amount;
        balances[msg.sender] += amount;
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "transfer failed");
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "amount=0");
        uint256 bal = balances[msg.sender];
        require(bal >= amount, "balance");
        balances[msg.sender] = bal - amount;
        totalStaked -= amount;
        require(stakingToken.transfer(msg.sender, amount), "transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(stakingToken.transfer(msg.sender, reward), "transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        getReward();
    }

    function notifyRewardAmount(uint256 reward, uint256 duration) external onlyOwner updateReward(address(0)) {
        require(duration > 0, "duration=0");
        uint256 balance = stakingToken.balanceOf(address(this)) - totalStaked;
        require(reward <= balance, "insufficient rewards");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / duration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / duration;
        }
        rewardsDuration = duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
        emit RewardConfigured(reward, duration);
    }
}
