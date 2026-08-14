// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockERC20 is IERC20 {
    string public name = "Obsidian Token";
    string public symbol = "OBS";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract ArizonaForestationDAOTest is Test {
    ArizonaForestationDAO public dao;
    MockERC20 public token;

    address owner = address(0x1);
    address relayer = address(0x2);
    address voter1 = address(0x3);
    address recipient = address(0x4);

    bytes32 constant MOCK_PQC_HASH = keccak256("PQC_HYBRID_SIGNATURE_ARIZONA_DAO");

    function setUp() public {
        vm.startPrank(owner);
        token = new MockERC20();
        dao = new ArizonaForestationDAO(address(token), relayer);
        
        token.mint(voter1, 100_000 * 10**18);
        token.mint(address(dao), 1_000_000 * 10**18);
        vm.stopPrank();
    }

    function test_DeploymentConfiguration() public view {
        assertEq(address(dao.obsToken()), address(token));
        assertEq(dao.robotExecutionRelayer(), relayer);
        assertEq(dao.owner(), owner);
        assertEq(dao.IPFS_CID(), "bafybeigdyrzt5sfp7udm7hu76uh7y26nf4dfuylqab5374y5374y5374y5");
    }

    function test_CreateProposal() public {
        vm.prank(voter1);
        uint256 proposalId = dao.createProposal(
            "Arizona forestation, off-grid solar, AWG and free bamboo distribution",
            10_000 * 10**18,
            payable(recipient),
            MOCK_PQC_HASH
        );

        assertEq(proposalId, 1);
        (
            uint256 id, 
            address proposer, 
            , 
            uint256 requestedFunds, 
            address rec, 
            , 
            , 
            , 
            bool executed, 
            , 
            bytes32 pqcHash
        ) = dao.proposals(1);

        assertEq(id, 1);
        assertEq(proposer, voter1);
        assertEq(requestedFunds, 10_000 * 10**18);
        assertEq(rec, recipient);
        assertFalse(executed);
        assertEq(pqcHash, MOCK_PQC_HASH);
    }

    function test_VotingAndQuorumExecution() public {
        vm.prank(voter1);
        dao.createProposal(
            "Solar & Water Gen Project",
            10_000 * 10**18,
            payable(recipient),
            MOCK_PQC_HASH
        );

        vm.prank(voter1);
        dao.vote(1, true);

        skip(4 days);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        dao.executeProposal(1);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + 10_000 * 10**18);
    }

    function test_RobotRelayerPQCExecution() public {
        vm.prank(voter1);
        dao.createProposal(
            "Automated Robot Array Irrigation & Bamboo Harvest",
            5_000 * 10**18,
            payable(recipient),
            MOCK_PQC_HASH
        );

        vm.prank(voter1);
        dao.vote(1, true);

        skip(4 days);

        vm.prank(relayer);
        dao.robotExecuteApprovedProposal(1, MOCK_PQC_HASH);

        (,,,,,,,, bool executed,,) = dao.proposals(1);
        assertTrue(executed);
    }
}
