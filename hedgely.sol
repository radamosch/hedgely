pragma solidity ^0.4.19;

// radamosch@gmail.com

// Contract based investment game

// 0xf8c4dbdc95c6bb06df29a15506f6186272c0894e

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {

  address public owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused public {
    paused = true;
    Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused public {
    paused = false;
    Unpause();
  }
}

/**
 * @title Syndicate
 * @dev Syndicated profit sharing - for early adopters
 * Shares are not transferrable -
 */
contract Syndicate is Ownable,Pausable{

    uint256 public totalSyndicateShares = 10000;
    uint256 public availableSyndicateShares = 5000; // how many slots are available
    //uint256 public maxSharesPerMember = 200; // !!??? todo
    uint256 public syndicateSharePrice = 1 finney; // 0.001 ether
    uint256 public shareCycleSessionSize = 10; // number of sessions in a share cycle
    uint256 public shareCycleIndex = 0; // current position in share cycle
    uint256 public currentSyndicateValue = 0; // total value of syndicate to be divided among memmbers
    uint256 public numberSyndicateMembers = 0;
    bool public shareCycleOverdue = false; // whether or not a profit sharing cycle should be processed.

    struct member {
        uint256 numShares;
        uint256 profitShare;
     }

    address[] private syndicateMembers;
    mapping(address => member ) private members;


    event ProfitShare(
          uint256 _currentSyndicateValue,
          uint256 _numberSyndicateMembers,
          uint256 _totalOwnedShares,
          uint256 _profitPerShare
    );

    function Syndicate() public {
        members[msg.sender].numShares = 5000; // owner portion
        members[msg.sender].profitShare = 0;
        numberSyndicateMembers = 1;
        syndicateMembers.push(msg.sender);
    }

    // initiates a dividend oif necessary, sends
    function claimDividend() public {
      if (members[msg.sender].numShares==0) revert(); // only syndicate members.

      // divide up the profits between the syndicate members
      if (shareCycleOverdue){

          uint256 totalOwnedShares = totalSyndicateShares-availableSyndicateShares;
          uint256 profitPerShare = SafeMath.div(currentSyndicateValue,totalOwnedShares);

          // foreach member , calculate their profitshare
          for(uint i = 0; i< numberSyndicateMembers; i++)
          {
            // do += so that acrues across share cycles.
            members[syndicateMembers[i]].profitShare+=SafeMath.mul(members[syndicateMembers[i]].numShares,profitPerShare);
          }

          // emit a profit share event
          ProfitShare(currentSyndicateValue, numberSyndicateMembers, totalOwnedShares , profitPerShare);

          currentSyndicateValue=0; // all the profit has been divided up
          shareCycleOverdue = false;
          shareCycleIndex = 0; // restart the share cycle count.
      }
      uint256 profitShare = members[msg.sender].profitShare;
      if (profitShare>0){
        members[msg.sender].profitShare = 0;
        msg.sender.transfer(profitShare);
      }
    }

    // allocate syndicate shares up to the limit.
    function allocateShares(uint256 value) internal {
         if (availableSyndicateShares==0) return;
         uint256 allocation = SafeMath.div(value,syndicateSharePrice);
         if (allocation >= availableSyndicateShares){
            allocation = availableSyndicateShares; // limit hit
         }
         availableSyndicateShares = SafeMath.sub(availableSyndicateShares, allocation);

         if (members[msg.sender].numShares == 0){
          syndicateMembers.push(msg.sender);
          numberSyndicateMembers++;
         } // add new member of syndicate
         members[msg.sender].numShares+=allocation;

    }

    // how many shares?
    function memberShareCount() public  view returns (uint256) {
        return members[msg.sender].numShares;
    }

}


/**
 * Core Hedgely Contract
 */
contract Hedgely is Ownable,Pausable, Syndicate {

   // Array of players
   address[] private players;
   mapping(address => bool) private activePlayers;
   uint256 numPlayers = 0;

   // map each player address to their portfolio of investments
   mapping(address => uint256 [10] ) private playerPortfolio;

   uint256 public totalHedgelyWinnings;
   uint256 public totalHedgelyInvested;

   uint256[10] private marketOptions;

   // The total amount of Ether bet for this current market
   uint256 public totalInvested;
   // The amount of Ether used to see the market
   uint256 public seedInvestment;


   // The total number of investments the users have made
   uint256 public numberOfInvestments;

   // The number that won the last game
   uint256 public numberWinner;


   uint256 public startingBlock;
   uint256 public endingBlock;
   uint256 public sessionBlockSize;

   uint256 public minimumStake = 1 finney;
   uint256 public precision = 1000000000000000;

   uint256 public sessionNumber;
   uint256 public currentLowest;
   uint256 public currentLowestCount; // should count the number of currentLowest to prevent a tie


     event Invest(
           address _from,
           uint256 _option,
           uint256 _value,
           uint256[10] _marketOptions,
           uint _blockNumber
     );


     event EndSession(
           uint256 _sessionNumber,
           uint256 _winningOption,
           uint256[10] _marketOptions,
           uint256 _blockNumber
     );

     event StartSession(
           uint256 _sessionNumber,
           uint256 _sessionBlockSize,
           uint256[10] _marketOptions,
           uint256 _blockNumber
     );

    bool locked;
    modifier noReentrancy() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

   function Hedgely() public {
     owner = msg.sender;
     sessionBlockSize = 100;
     sessionNumber = 0;
     totalHedgelyWinnings = 0;
     totalHedgelyInvested = 0;
     numPlayers = 0;
     resetMarket();
   }

    // the full amount invested in each option
   function getMarketOptions() public constant returns (uint256[10])
    {
        return marketOptions;
    }

    // each player can get their own portfolio
   function getPlayerPortfolio() public constant returns (uint256[10])
    {
        return playerPortfolio[msg.sender];
    }

    // the number of investors this session
    function numberOfInvestors() public constant returns(uint count) {
        return numPlayers;
    }

    // generate a random number between 1 and 20 to seed a symbol
    function rand() internal returns (uint64) {
      return random(19)+1;
    }

    // pseudo random - but does that matter?
    uint64 _seed = 0;
    function random(uint64 upper) private returns (uint64 randomNumber) {
       _seed = uint64(keccak256(keccak256(block.blockhash(block.number), _seed), now));
       return _seed % upper;
     }

    // resets the market conditions
   function resetMarket() internal {

      sessionNumber ++;
      startingBlock = block.number;
      endingBlock = startingBlock + sessionBlockSize; // approximately every 5 minutes - can play with this
      clearPlayers();

     uint256 sumInvested = 0;

     for(uint i=0;i<10;i++)
      {
          uint256 num =  rand();
          marketOptions[i] =num*precision; // wei
          sumInvested+=  marketOptions[i];
      }

     playerPortfolio[this] = marketOptions;
     totalInvested =  sumInvested;
     seedInvestment = sumInvested;
     insertPlayer(this);
     numPlayers=1;
     numberOfInvestments = 10;

     currentLowest = findCurrentLowest();
     StartSession(sessionNumber, sessionBlockSize, marketOptions , startingBlock);

   }


    function roundIt(uint256 amount) internal constant returns (uint256)
    {
        // round down to correct preicision
        uint256 result = (amount/precision)*precision;
        return result;
    }

    // main entry point for investors/players
    function invest(uint256 optionNumber) public payable noReentrancy whenNotPaused {

      // Check that the number to bet is within the range
      assert(optionNumber >= 0 && optionNumber <= 9);
      uint256 amount = roundIt(msg.value); // round to precision
      assert(amount >= minimumStake);

      uint256 holding = playerPortfolio[msg.sender][optionNumber];
      holding = SafeMath.add(holding, amount);
      playerPortfolio[msg.sender][optionNumber] = holding;

      marketOptions[optionNumber] = SafeMath.add(marketOptions[optionNumber],amount);

      numberOfInvestments += 1;
      totalInvested += amount;
      totalHedgelyInvested += amount;
      if (!activePlayers[msg.sender]){
                    insertPlayer(msg.sender);
                    activePlayers[msg.sender]=true;
       }

      Invest(msg.sender, optionNumber, amount, marketOptions, block.number);

      // possibly allocate syndicate shares
      allocateShares(amount);

      currentLowest = findCurrentLowest();
      if (block.number >= endingBlock && currentLowestCount==1) distributeWinnings();

    } // end invest


    // find lowest option sets currentLowestCount>1 if there are more than 1 lowest
    function findCurrentLowest() internal returns (uint lowestOption) {

      uint winner = 0;
      uint lowestTotal = marketOptions[0];
      currentLowestCount = 0;

      for(uint i=0;i<10;i++)
      {
          if (marketOptions [i]<lowestTotal){
              winner = i;
              lowestTotal = marketOptions [i];
              currentLowestCount = 0;
          }
         if (marketOptions [i]==lowestTotal){currentLowestCount+=1;}
      }

      return winner;

    }

    // distribute winnings at the end of a session
    function distributeWinnings() internal {

         if (currentLowestCount>1){
           return; // cannot end session because there is no lowest.
         }

         numberWinner = currentLowest;

        // record the end of session
        EndSession(sessionNumber, numberWinner, marketOptions , block.number);

        uint256 sessionWinnings = 0;
        for(uint j=1;j<numPlayers;j++)
        {
              if (playerPortfolio[players[j]][numberWinner]>0){
                uint256 winningAmount =  playerPortfolio[players[j]][numberWinner];
                uint256 winnings = SafeMath.mul(8,winningAmount); // eight times the invested amount.
                totalHedgelyWinnings+=winnings;
                sessionWinnings+=winnings;
                players[j].transfer(winnings); // don't throw here
              }
              playerPortfolio[players[j]] = [0,0,0,0,0,0,0,0,0,0];
              activePlayers[players[j]]=false;

        }

        // calculate session profit and add to the syndicated value
        uint256 sessionProfit = SafeMath.sub(SafeMath.sub(totalInvested,seedInvestment),sessionWinnings);
        currentSyndicateValue+=sessionProfit;

        resetMarket();

        // increment share cycle index as this session has ended
        shareCycleIndex+=1;
        if (!shareCycleOverdue && shareCycleIndex >= shareCycleSessionSize){
          shareCycleOverdue = true; // allows syndicate members to claim dividend
        }

    }



    function insertPlayer(address value) internal {
        if(numPlayers == players.length) {
            players.length += 1;
        }
        players[numPlayers++] = value;
    }

    function clearPlayers() internal {
        numPlayers = 0;
    }

   // We might vary this at some point
    function setsessionBlockSize (uint256 blockCount) public onlyOwner {
        sessionBlockSize = blockCount;
    }


   // Could be needed
    function withdraw(uint256 amount) public onlyOwner {
        require(amount<=this.balance);
        if (amount==0){
            amount=this.balance;
        }
        owner.transfer(amount);
    }


   // In the event of catastrophe
    function kill()  public onlyOwner{
         if(msg.sender == owner)
            selfdestruct(owner);
    }

    // donations, funding, replenish
     function() public payable {}


}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  /**
  * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}
