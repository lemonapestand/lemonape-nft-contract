pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
//SPDX-License-Identifier: MIT

/// @notice Thrown when completing the transaction results in overallocation of LemonApe Stands.
error MintedOut();
/// @notice Thrown when a user is trying to upgrade a stand, but does not have the previous stand in the upgrade flow.
error MissingPerviousStand();
/// @notice Thrown when the dutch auction phase has not yet started, or has already ended.
error MintNotStarted();
/// @notice Thrown when the user has already minted two LemonApe Stands in the dutch auction.
error MintingTooMany();
/// @notice Thrown when the value of the transaction is not enough for the current dutch auction or mintlist price.
error ValueTooLow();
/// @notice Thrown when a user is trying to upgrade past the highest stand level.
error MissingPreviousNFT();
/// @notice Thrown when a user doesn't have the previous stand level.
error UnknownUpgrade();

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom( address from, address to, uint256 amount) external returns (bool);
}

abstract contract ERC721 {
    /*///////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*///////////////////////////////////////////////////////////////
                          METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*///////////////////////////////////////////////////////////////
                            ERC721 STORAGE                        
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    /// @notice The current price to mint a Lemon Stand
    uint256 public currentLemonStandPrice;

    mapping(address => uint256) public balanceOf;

    mapping(uint256 => address) public ownerOf;

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;


    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*///////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || msg.sender == getApproved[id] || isApprovedForAll[from][msg.sender],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            balanceOf[from]--;

            balanceOf[to]++;
        }

        ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);

        _addTokenToOwnerEnumeration(to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public virtual {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*///////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual  returns (uint256) {
        require(index < balanceOf[owner], "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf[to];
        _ownedTokens[to][length] = tokenId;
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
interface ERC721TokenReceiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4);
}

/// @title Generation 0 and 1 LemonApeStand NFTs
// contract LemonApeStandNFT is ERC721, Ownable {
contract LemonApeStandNFT is ERC721, Ownable {
    using Strings for uint256;

    /*///////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Determines the order of the species for each tokenId, mechanism for choosing starting index explained post mint, explanation hash: acb427e920bde46de95103f14b8e57798a603abcf87ff9d4163e5f61c6a56881.
    uint constant public provenanceHash = 0x9912e067bd3802c3b007ce40b6c125160d2ccb5352d199e20c092fdc17af8057;

    /// @dev Sole receiver of collected contract $LAS
    address constant stakingContract = 0x000000000000000000000000000000000000dEaD;

    /// @dev Address of $LAS to mint Lemon Stands
    address private lasToken = 0x84c071CbFa571Af3c6c966f80530867D0d407F6E;

    /// @dev Address of $POTION to mint higher tier stands
    address private potionToken = 0x980693AbB2D6A92Bc67e95C9c646d24275D8236d;

    /// @dev 5000 total nfts can ever be made
    uint constant mintSupply = 425;

    /// @dev The offsets are the tokenIds that the corresponding evolution stage will begin minting at.
    uint constant grapeStandOffset = 300;
    uint constant dragonStandOffset = grapeStandOffset + 100;
    uint constant fourTwentyStandOffset = dragonStandOffset + 25;

    /*///////////////////////////////////////////////////////////////
                        UPGRADE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The next tokenID to be minted for each of the stand stages
    uint gen0_LemonStandSupply = 300;
    uint grapeStandSupply = 100;
    uint dragonStandSupply = 25;
    uint fourTwentyStandSupply = 10;

    /*///////////////////////////////////////////////////////////////
                            MINT STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice The timestamp the minting for Lemon Stands started
    uint256 public mintStartTime;

    /// @notice The timestamp of the last time a Lemon Stand was minted
    uint256 public lastTimeMinted;

    /// @notice The current generation mint phase
    bool public isGen0Mint;

    /// @notice Starting price of the Lemon Stand in $LAS (1,000 $LAS)
    uint256 constant public startPrice = 1000 * 10**18;

    uint256 public mintLimit = 2;

    /*///////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public baseURI;

    /*///////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys the contract, airdropping to presalers.
    // constructor(string memory _baseURI) ERC721("LEMONAPESTAND NFT", "LASNFT") {
    constructor(string memory _baseURI, address[] memory dropLemonStands) ERC721("LEMONAPESTAND NFT", "LASNFT") {
        baseURI = _baseURI;
        unchecked {
            totalSupply += dropLemonStands.length;
            for (uint256 i = 0; i < dropLemonStands.length; i++) {
                ownerOf[i] = dropLemonStands[i];
                balanceOf[msg.sender] = 1;
                emit Transfer(address(0), msg.sender, i);
            }
        }
    }

    function setMintLimit(uint256 _mintLimit) public onlyOwner {
        mintLimit = _mintLimit;
    }

    /*///////////////////////////////////////////////////////////////
                            METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows the contract deployer to set the metadata URI.
    /// @param _baseURI The new metadata URI.
    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, id.toString()));
    }

    /*///////////////////////////////////////////////////////////////
                        REVERSE-DUTCH AUCTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates the mint price with the accumulated rate deduction since the mint's started. Every hour there is no mint the price goes down 100 tokens. After every mint the price goes up 100 tokens.
    /// @return The mint price at the current time, or 0 if the deductions are greater than the mint's start price.
    function getCurrentTokenPrice() private view returns (uint) {
        uint priceReduction = ((block.timestamp - lastTimeMinted) / 1 hours) * 100 * 10**18;
        return currentLemonStandPrice >= priceReduction ? (currentLemonStandPrice - priceReduction) :  100 * 10**18;
    }

    /// @notice Purchases a LemonApeStand NFT in the reverse-dutch auction
    /// @param amountToMint the amount of NFTs to mint in one transcation.
    function mint(uint256 amountToMint) public {
        if(block.timestamp < mintStartTime) revert MintNotStarted();
        uint price = getCurrentTokenPrice();
        if(IERC20(lasToken).balanceOf(msg.sender) < price * amountToMint) revert ValueTooLow();
        if(balanceOf[msg.sender] + amountToMint > amountToMint) revert MintingTooMany();
        if(totalSupply + amountToMint > mintSupply) revert MintedOut();

        for (uint256 i = 0; i < amountToMint; i++) {
            uint256 mintIndex = totalSupply;
            _mint(msg.sender, mintIndex);
        }        
    }

    /*///////////////////////////////////////////////////////////////
                       INTERNAL MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");
        require(ownerOf[id] == address(0), "ALREADY_MINTED");

        IERC20(lasToken).transferFrom(msg.sender, stakingContract, currentLemonStandPrice);
        // Counter overflow is incredibly unrealistic.
        unchecked {
            totalSupply++;
            balanceOf[to]++;
        }
        ownerOf[id] = to;

        emit Transfer(address(0), to, id);
        currentLemonStandPrice += 100 * 10**18;
    }

    /*///////////////////////////////////////////////////////////////
                        UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints an upgraded LemonApe Stand
    /// @param receiver Receiver of the upgraded LemonApe Stand
    /// @param standIdToUpgrade The upgrade (2-4) that the LemonApeStand NFT is undergoing
    function mintUpgradedStand(address receiver, uint standIdToUpgrade) public {
        if(block.timestamp < mintStartTime) revert MintNotStarted();
        uint upgradeToStand;
        if(standIdToUpgrade <= 300){
            upgradeToStand = 2;
        } else if(standIdToUpgrade <= 400){
            upgradeToStand = 3;
        } else if(standIdToUpgrade <= 425){
            upgradeToStand = 4;
        } else {
            revert UnknownUpgrade();
        }

        if (upgradeToStand == 2) {
            if(grapeStandSupply >= 100) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 1 * 10**18) revert ValueTooLow();
            if(!isExistVersionOfNFT(receiver, 1)) revert MissingPreviousNFT();
            IERC20(potionToken).transferFrom(msg.sender, stakingContract, 1 * 10**18);
            _mint(receiver, grapeStandOffset + grapeStandSupply);
            unchecked {
                grapeStandSupply++;
            }
        } else if (upgradeToStand == 3) {
            if(dragonStandSupply >= 25) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 2 * 10**18) revert ValueTooLow();
            if(!isExistVersionOfNFT(receiver, 2)) revert MissingPreviousNFT();
            IERC20(potionToken).transferFrom(msg.sender, stakingContract, 2 * 10**18);
            _mint(receiver, dragonStandOffset + dragonStandSupply);
            unchecked {
                dragonStandSupply++;
            }
        } else if (upgradeToStand == 4) {
            if(fourTwentyStandSupply >= 10) revert MintedOut();
            if(IERC20(potionToken).balanceOf(msg.sender) < 3 * 10**18) revert ValueTooLow();
            if(!isExistVersionOfNFT(receiver, 3)) revert MissingPreviousNFT();
            IERC20(potionToken).transferFrom(msg.sender, stakingContract, 3 * 10**18);
            _mint(receiver, fourTwentyStandOffset + fourTwentyStandSupply);
            unchecked {
                fourTwentyStandSupply++;
            }
        } else  {
            revert UnknownUpgrade();
        }
    }
    /*///////////////////////////////////////////////////////////////
        This is a function to check what version NFT 
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints an upgraded LemonApe Stand
    /// @param id Id of the NFT
    /// @return version of the NFT

    function getVersionFromNFTId(uint id) public view returns (uint version) 
    {

        if(id<=grapeStandOffset){
            return 1;
        }
        else if(id<=dragonStandOffset){
            return 2;
        }
        else if(id<=fourTwentyStandOffset)
        {
            return 3;
        }
        else if(id<=fourTwentyStandOffset+fourTwentyStandSupply){
            return 4;
        }
        else{
            return 0;
        }
    }

    /// Get all Ids of tokens user does have
    /// @param _owner Address ot the selcted user
    /// @return array of Id of tokens
    function walletOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf[_owner];

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
             tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    /// Check if the user has version of the NFT
    /// @param _owner Address of the selected user
    /// @param version Version Number of the NFT to check if user has
    /// @return isExist true if it's exist
    function isExistVersionOfNFT(address _owner, uint version) public view returns (bool isExist) {
        uint256[] memory tokensId;
        tokensId = walletOfOwner(_owner);
        for (uint256 i = 0; i < tokensId.length; i++) {
            if (getVersionFromNFTId(tokensId[i])==version) return true;
        }
        return false;
    }

}
