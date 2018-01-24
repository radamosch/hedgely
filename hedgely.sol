pragma solidity ^0.4.19;

import "https://github.com/axiomzen/eth-random/contracts/Random.sol";


// radamosch@gmail.com

// Contract based investment game
//0xc8bad665c5c107810f1dd4eed87c5e64d0cf0f47



contract Hedgely {


  address owner;

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

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

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


    Random api = Random(0x1637140C895e01d14be5a7A42Ec2c5BB22893713);

    function rand() internal returns (uint64) {
      return api.random(20);
    }

    // resets the market conditions
   function resetMarket() internal {

      sessionNumber ++;
      totalInvested = 0;
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
     totalInvested = totalInvested + sumInvested;
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
    function invest(uint256 optionNumber) public payable noReentrancy {

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

        for(uint j=1;j<numPlayers;j++)
        {
              if (playerPortfolio[players[j]][numberWinner]>0){
                uint256 winningAmount =  playerPortfolio[players[j]][numberWinner];
                uint256 winnings = SafeMath.mul(8,winningAmount); // eight times the invested amount.
                totalHedgelyWinnings+=winnings;
                players[j].transfer(winnings); // don't throw here
              }
              playerPortfolio[players[j]] = [0,0,0,0,0,0,0,0,0,0];
              activePlayers[players[j]]=false;

        }

        resetMarket();
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
