// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/stdlib.sol";
import "./interfaces/HEVM.sol";

import "../Marketplace.sol";
import "./mocks/MockERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Receiver is IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 id,
        bytes calldata data
    ) external returns (bytes4){
        return this.onERC721Received.selector;
    }
}

contract MarketplaceTest is DSTest, Receiver, Marketplace {
    Marketplace public marketplace;
    MockERC721 public mockNft;

    address constant bob= address(0x1337);
    address constant alice = address(0x1111);

    Vm vm = Vm(HEVM_ADDRESS);
    using stdStorage for StdStorage;
    StdStorage private stdstore;

    //setup
    function setUp() public {
        marketplace = new Marketplace();
        mockNft = new MockERC721();
    }

    //test mocks
    function testMint() public {
        bool pass = mockNft.mintItem("testURI");
        assertTrue(pass);
    }
    function testMintTwo() public {
        vm.startPrank(alice);
        mockNft.mintItem("testURI");
        mockNft.mintItem("testURI2");
        mockNft.approve(address(marketplace), 1);
        marketplace.createListing(
            address(mockNft),
            1,
            1 ether,
            false,
            3600
        );
        vm.stopPrank();

        uint256 slotBalance = stdstore
            .target(address(mockNft))
            .sig(mockNft.balanceOf.selector)
            .with_key(alice)
            .find();
        uint256 balance = uint256(vm.load(address(mockNft), bytes32(slotBalance)));
        assertEq(balance, 2);
    }

    function _createListing(
        address nftContract,
        uint256 nftId,
        uint256 price,
        bool isAuction,
        uint256 biddingTime
    ) public {
        marketplace.createListing(nftContract, nftId, price, isAuction, biddingTime);
        uint256 p = marketplace.getPrice(1);
        assertEq(p, price);
    }

    function testBuyListing() public {
        vm.startPrank(alice);
        mockNft.mintItem("testURI");
        mockNft.mintItem("testURI2");
        mockNft.approve(address(marketplace), 1);
        marketplace.createListing(
            address(mockNft),
            1,
            1 ether,
            false,
            3600
        );
        vm.stopPrank();
        //create receiver
        //Receiver receiver = new Receiver();

        marketplace.buy{value: 1 ether}(1);

        uint256 slotBalance = stdstore
            .target(address(mockNft))
            .sig(mockNft.balanceOf.selector)
            .with_key(alice)
            .find();
        uint256 balance = uint256(vm.load(address(mockNft), bytes32(slotBalance)));
        assertEq(balance, 1);
    }

    function setRoyalties(uint256 royaltyAmount, address payoutAccount) public {
        marketplace.setNFTCollectionRoyalty(address(mockNft),'YourCollectible',payoutAccount,royaltyAmount);
    }
}
