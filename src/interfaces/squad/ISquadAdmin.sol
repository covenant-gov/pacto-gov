// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ISquadAdminBase} from 'interfaces/squad/ISquadAdminBase.sol';
import {IHatGated} from 'interfaces/utils/IHatGated.sol';

/**
 * @title ISquadAdmin
 * @author Pacto
 * @notice `ISquadAdminBase` roster API plus clone `initialize` and hat-id views. Not upgradeable;
 *      use fresh EIP-1167 instances if logic must change.
 */
interface ISquadAdmin is ISquadAdminBase, IHatGated {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Parameters required to initialize a squad-admin clone.
   * @param captainHatId Captain hat id that gates executor management.
   * @param squadAdminHatId Squad-admin hat id minted to this clone; stored for discovery (`squadAdminHatId()` without registry reads).
   */
  struct InitParams {
    uint256 captainHatId;
    uint256 squadAdminHatId;
  }

  /*///////////////////////////////////////////////////////////////
                        CONSTRUCTOR / INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice One-shot initializer for a clone; seeds the captain and squad-admin hat ids.
   * @param _p Bootstrap parameters.
   */
  function initialize(InitParams calldata _p) external;

  /**
   * @notice One-shot initializer for a clone; seeds the captain hat id only.
   * @param _ownerHatId Owner hat id (same as `captainHatId`).
   */
  function initialize(uint256 _ownerHatId) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Access-gated hook to persist full hat bootstrap params (e.g. governance migration).
   * @param _p Hat ids to store.
   */
  function postInitialize(InitParams calldata _p) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Captain hat id used for gate checks in v1.
   * @return _captainHatId Hat id
   */
  function captainHatId() external view returns (uint256 _captainHatId);

  /**
   * @notice Squad-admin hat id for this clone (discovery helper; not used for roster gates in v1).
   * @return _squadAdminHatId Hat id
   */
  function squadAdminHatId() external view returns (uint256 _squadAdminHatId);
}
