//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Collection royalties
//   This can be setup by a collection owner right after NFT contract deployment.
//   The collection owner enters the deployment address of the collection and the
//   collections name as it appears in the smart contract, the royalty amount, and the royalty recievers address.


import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// * * * TESTING ONLY * * *
//import "hardhat/console.sol";

contract Marketplace is ReentrancyGuard, Ownable {
    // * Utils
    using Counters for Counters.Counter;
    Counters.Counter private listingIds;

    // * State
    mapping(uint256 => Listing) public listings;
    mapping(address => Royalties) public royalties; // royalty information by collection address.

    uint256 public constant BPS = 10000;

    // * Structs
    // Single NFT listing
    struct Listing {
        address nftContract;
        uint256 nftId;
        address payable seller;
        uint256 price;
        uint256 bid;
        bool isAuction;
        uint256 date;
        address highestBidder;
    }
    // NFT collection
    struct Collection {
        address payable royaltyPaidTo;
        uint256 royaltyPercent;
    }

    struct Royalties {
        address _nftContract;
        string _collectionName;
        address payoutAccount;
        uint256 royaltyAmount;
        bool exists;
    }

    // * Events
    event ListingCreated(
        uint256 listingId,
        address indexed nftContract,
        uint256 indexed nftId,
        address seller,
        uint256 price,
        uint256 bid,
        bool isAuction,
        uint256 date,
        address highestBidder
    );
    event Purchase(uint256 indexed itemId, address buyer, uint256 price);
    event UpdatedPrice(uint256 indexed itemId, address owner, uint256 price);
    event NewBid(address buyer, Listing listing, uint256 bid);

    // * Listing owner modifier
    modifier Owned(uint256 listingId) {
        Listing memory item = listings[listingId];
        address ownerOfToken = IERC721(item.nftContract).ownerOf(item.nftId);

        require(ownerOfToken == msg.sender, "You don't own this NFT!");
        _;
    }

    // * Constructor
    constructor() {}

    // * Create Listing
    function createListing(
        address nftContract,
        uint256 nftId,
        uint256 price,
        bool isAuction,
        uint256 biddingTime
    ) public nonReentrant {
        require(price > 0, "Price must be greater than 0.");
        address nftOwner = IERC721(nftContract).ownerOf(nftId);
        require(nftOwner == msg.sender, "You can't sell an NFT you don't own!");
        if (isAuction) {
            require(biddingTime > 0, "Auctions must have a valid date");
        }

        listingIds.increment();
        uint256 itemId = listingIds.current();
        uint256 auctionDate = block.timestamp + biddingTime;
        uint256 startingBid = isAuction ? price : 0;

        listings[itemId] = Listing(
            nftContract,
            nftId,
            payable(msg.sender),
            price,
            startingBid,
            isAuction,
            auctionDate,
            payable(address(0))
        );
        emit ListingCreated(
            itemId,
            nftContract,
            nftId,
            msg.sender,
            price,
            startingBid,
            isAuction,
            auctionDate,
            address(0)
        );
    }

    // eMax or ETH buy function
    function buy(uint256 listingId) public payable nonReentrant {
        Listing memory item = listings[listingId];
        require(item.nftContract != address(0x0000), "Listing does not exist.");
        address contractAddress = item.nftContract;
        address nftSeller = item.seller;
        uint256 nftId = item.nftId;
        uint256 price = item.price;
        uint256 baseRoyalty = royalties[contractAddress].royaltyAmount;
        address royaltyReciever = royalties[contractAddress].payoutAccount;

        // validate amount sent is enough to buy NFT
        require(
            msg.value >= price,
            "Please submit asking price in order to complete purchase"
        );

        // seller must call approve on the marketplace contract for transfer
        IERC721(contractAddress).safeTransferFrom(nftSeller, msg.sender, nftId);

        //console.log((price * baseRoyalty) / BPS); //just royalty amount
        payable(nftSeller).transfer(price - ((price * baseRoyalty) / BPS)); // price - royalty
        payable(royaltyReciever).transfer((price * baseRoyalty) / BPS); //just royalty
        emit Purchase(listingId, msg.sender, price);
    }

    // * Get current listing price
    function getPrice(uint256 listingId) public view returns (uint256) {
        return listings[listingId].price;
    }

    function updatePrice(uint256 listingId, uint256 newPrice)
        public
        Owned(listingId)
    {
        listings[listingId].price = newPrice;
        emit UpdatedPrice(listingId, msg.sender, newPrice);
    }

    // * Get current bid
    function getCurrentBid(uint256 listingId) public view returns (uint256) {
        return listings[listingId].bid;
    }

    // * Transfer current bid to seller and NFT to winner
    function withdraw(uint256 listingId) public nonReentrant {
        Listing storage listing = listings[listingId];
        address contractAddress = listing.nftContract;
        uint256 nftId = listing.nftId;
        address nftSeller = listing.seller;
        address highestBidder = listing.highestBidder;
        uint256 endBid = listing.bid;
        uint256 baseRoyalty = royalties[contractAddress].royaltyAmount;
        address royaltyReceiver = royalties[contractAddress].payoutAccount;

        IERC721(contractAddress).safeTransferFrom(
            nftSeller,
            highestBidder,
            nftId
        );

        payable(nftSeller).transfer(endBid - ((endBid * baseRoyalty) / BPS));
        payable(royaltyReceiver).transfer((endBid * baseRoyalty) / BPS);

        payable(nftSeller).transfer(endBid); // price only

        //update listing status
        listing.isAuction = false;

        emit Purchase(listingId, highestBidder, endBid);
    }

    // * Manual early cancellation by seller
    function auctionCancel(uint256 listingId)
        public
        Owned(listingId)
        nonReentrant
    {
        Listing storage listing = listings[listingId];
        require(block.timestamp < listing.date, "Auction has already ended");
        // if there is a highestBidder, transfer them back their bid.
        if (listing.highestBidder != address(0))
            payable(listing.highestBidder).transfer(listing.bid);

        delete listings[listingId];
    }

    // * Manually remove a listing if you are the owner and the auction is set to false.
    function removeListing(uint256 listingId) public Owned(listingId) {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "You do not own this listing.");
        require(
            listing.isAuction == false,
            "You cannot remove an active auction"
        );

        delete listings[listingId];
    }

    // ============ UTILITIES ==============

    // * If msg.value is greater than listing price in ETH, refund the difference
    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    // * Set royalties for a NFT collection. Owners of an NFT collection to use this function to set up
    //   royalties for their collections. The address given will be where the collection royalties are sent to
    function setNFTCollectionRoyalty(
        address contractAddress,
        string memory collectionName,
        address payoutAccount,
        uint256 royaltyAmount
    ) public returns (bool) {
        require(
            !royalties[contractAddress].exists,
            "Collection already has royalty info set."
        );
        require(
            royaltyAmount > 0 && royaltyAmount <= 5000,
            "Please set a royalty amount between 0.01% and 50%"
        );
        require(payoutAccount  != address(0), "Royalties should not be burned.");
        // set royalties
        royalties[contractAddress] = Royalties(
            contractAddress,
            collectionName,
            payoutAccount,
            royaltyAmount,
            true
        );

        return true;
    }

    // ========= Receive =============
    // needed for contract to receive funds
    receive() external payable {}

    // ========= Only Owner =============

    function inCaseERC20GetsStuck(
        address to,
        IERC20 currency,
        uint256 amount
    ) public onlyOwner {
        IERC20(currency).transferFrom(address(this), to, amount);
    }
}
