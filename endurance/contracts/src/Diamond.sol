// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Minimal EIP-2535 (Diamond) implementation — selector->facet routing, a delegatecall
// fallback, an owner-gated diamondCut, and a loupe. Two stateful facets (Counter, Registry)
// store into a fixed-slot AppStorage so calls THROUGH the diamond mutate the diamond's own
// storage. The endurance workload calls facet functions via the diamond address; both facet
// ops are unconditional => revert-safe.

struct FacetCut { address facetAddress; bytes4[] functionSelectors; }

/// @notice Diamond routing storage (which facet serves which selector) at a fixed slot.
library LibDiamond {
    bytes32 internal constant DS_POS = keccak256("gemba.endurance.diamond.storage.v1");

    struct DiamondStorage {
        mapping(bytes4 => address) facets; // selector => facet
        bytes4[] selectors;                // all registered selectors (loupe)
        address owner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 p = DS_POS;
        assembly { ds.slot := p }
    }
    function owner() internal view returns (address) { return diamondStorage().owner; }
    function setOwner(address o) internal { diamondStorage().owner = o; }

    function addFunctions(FacetCut[] memory cuts) internal {
        DiamondStorage storage ds = diamondStorage();
        for (uint256 i; i < cuts.length; i++) {
            address facet = cuts[i].facetAddress;
            require(facet != address(0), "cut: zero facet");
            bytes4[] memory sels = cuts[i].functionSelectors;
            for (uint256 j; j < sels.length; j++) {
                require(ds.facets[sels[j]] == address(0), "cut: selector exists");
                ds.facets[sels[j]] = facet;
                ds.selectors.push(sels[j]);
            }
        }
    }
}

/// @notice Application storage shared by the facets (lives in the diamond's storage).
library LibApp {
    bytes32 internal constant APP_POS = keccak256("gemba.endurance.app.storage.v1");

    struct AppStorage {
        uint256 counter;
        mapping(address => uint256) userValue;
        mapping(address => uint256) userPings;
        uint256 totalPings;
    }

    function appStorage() internal pure returns (AppStorage storage a) {
        bytes32 p = APP_POS;
        assembly { a.slot := p }
    }
}

contract Diamond {
    constructor(FacetCut[] memory cuts, address owner_) {
        require(owner_ != address(0), "zero owner");
        LibDiamond.setOwner(owner_);
        LibDiamond.addFunctions(cuts);
    }

    /// @notice Add facets/selectors (EIP-2535 cut, add-only here). Owner-gated.
    function diamondCut(FacetCut[] memory cuts) external {
        require(msg.sender == LibDiamond.owner(), "not owner");
        LibDiamond.addFunctions(cuts);
    }

    fallback() external payable {
        address facet = LibDiamond.diamondStorage().facets[msg.sig];
        require(facet != address(0), "Diamond: selector not found");
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @notice Stateful facet — bumps a global counter in the diamond's storage.
contract CounterFacet {
    event Bumped(address indexed who, uint256 newValue);
    function increment() external {
        LibApp.AppStorage storage a = LibApp.appStorage();
        a.counter += 1;
        emit Bumped(msg.sender, a.counter);
    }
    function counter() external view returns (uint256) { return LibApp.appStorage().counter; }
}

/// @notice Stateful facet — per-user registry entry in the diamond's storage.
contract RegistryFacet {
    event EntrySet(address indexed who, uint256 value);
    function setEntry(uint256 v) external {
        LibApp.AppStorage storage a = LibApp.appStorage();
        a.userValue[msg.sender] = v;
        a.userPings[msg.sender] += 1;
        a.totalPings += 1;
        emit EntrySet(msg.sender, v);
    }
    function entryOf(address u) external view returns (uint256) { return LibApp.appStorage().userValue[u]; }
    function pingsOf(address u) external view returns (uint256) { return LibApp.appStorage().userPings[u]; }
    function totalPings() external view returns (uint256) { return LibApp.appStorage().totalPings; }
}

/// @notice Loupe — introspection over the diamond's selector routing.
contract LoupeFacet {
    function facetForSelector(bytes4 sel) external view returns (address) { return LibDiamond.diamondStorage().facets[sel]; }
    function allSelectors() external view returns (bytes4[] memory) { return LibDiamond.diamondStorage().selectors; }
    function diamondOwner() external view returns (address) { return LibDiamond.owner(); }
}
