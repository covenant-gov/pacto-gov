// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ISponsorPolicyRegistry
 * @notice Minimal registrar surface used by `NavePirataFactory`; full API lives in pacto-username-nft.
 */
interface ISponsorPolicyRegistry {
  /**
   * @notice Thrown when a caller is not an authorized registrar.
   * @param caller Unauthorized caller address.
   */
  error SponsorPolicyRegistry_UnauthorizedRegistrar(address caller);

  /**
   * @notice Thrown when a module is already indexed to a different topHat.
   * @param module Gov module address already indexed elsewhere.
   * @param existingTopHatId TopHat id the module is already bound to.
   */
  error SponsorPolicyRegistry_ModuleAlreadyIndexed(address module, uint256 existingTopHatId);

  /**
   * @notice Registers a topHat squad tree for global sponsorship.
   * @param topHatId Squad tophat id to register.
   */
  function registerTopHat(uint256 topHatId) external;

  /**
   * @notice Indexes gov module addresses to a topHat squad tree.
   * @param topHatId Squad tophat id these modules belong to.
   * @param modules Gov module addresses to index.
   */
  function registerModulesForTopHat(uint256 topHatId, address[] calldata modules) external;

  /**
   * @notice Returns the topHat id indexed for a gov module.
   * @param module Gov module address.
   * @return topHatId Indexed topHat id, or zero when unregistered.
   */
  function moduleToTopHat(address module) external view returns (uint256 topHatId);

  /**
   * @notice Returns whether a topHat squad tree is sponsorable.
   * @param topHatId Squad tophat id.
   * @return sponsored True when the tree is registered for sponsorship.
   */
  function isTopHatSponsored(uint256 topHatId) external view returns (bool sponsored);
}
