// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {INavePirataRegistry} from 'interfaces/factory/INavePirataRegistry.sol';

/**
 * @title IWarGameRegistry
 * @author Pacto
 * @notice Throwaway war-game index keyed by `squadId`. At most one Active stack per squad; history is append-only.
 *         Only the wired `NavePirataFactory` may write. Not the production `NavePirataRegistry`.
 */
interface IWarGameRegistry {
  /*///////////////////////////////////////////////////////////////
                            TYPES
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Lifecycle of a war-game stack.
   * @param Active Current stack for that `squadId` (at most one).
   * @param Retired Previous stack, kept for history.
   */
  enum Status {
    Active,
    Retired
  }

  /**
   * @notice Stored war-game row. Nested production `Deployment` is unchanged.
   * @param deployment Same fields as `INavePirataRegistry.Deployment`.
   * @param squadId MLS-parent key (`keccak256`) supplied in `DeployParams` for war-game.
   * @param status Active or Retired.
   */
  struct Record {
    INavePirataRegistry.Deployment deployment;
    bytes32 squadId;
    Status status;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice A war-game stack became Active for `_squadId`.
   * @param _squadId Squad key.
   * @param _topHatId Tophat id of the new Active stack.
   * @param _deployment Nested production deployment record.
   */
  event WarGameRegistered(
    bytes32 indexed _squadId, uint256 indexed _topHatId, INavePirataRegistry.Deployment _deployment
  );

  /**
   * @notice An Active war-game stack was retired (explicit `retire` or auto-retire on the next register).
   * @param _squadId Squad key.
   * @param _topHatId Tophat id that left Active.
   */
  event WarGameRetired(bytes32 indexed _squadId, uint256 indexed _topHatId);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Caller is not the registered factory.
   * @param _caller Calling address.
   */
  error WarGameRegistry_NotFactory(address _caller);

  /**
   * @notice A stack with that `topHatId` is already registered.
   * @param _topHatId The duplicated tophat id.
   */
  error WarGameRegistry_AlreadyRegistered(uint256 _topHatId);

  /**
   * @notice No Active war-game exists for that `squadId`.
   * @param _squadId The squad key with no Active stack.
   */
  error WarGameRegistry_NoActive(bytes32 _squadId);

  /// @notice `squadId` was `bytes32(0)` where a non-zero key was required.
  error WarGameRegistry_ZeroSquadId();
  /// @notice The factory wiring has already been set; `initialize` is one-shot.
  error WarGameRegistry_AlreadyWired();
  /// @notice A zero address was provided where a non-zero contract address was required.
  error WarGameRegistry_ZeroAddress();

  /*///////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice One-shot wiring for factory write access. Reverts after the first successful call.
   * @param _factory Address of the `NavePirataFactory` authorised to register and retire.
   */
  function initialize(address _factory) external;

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Record a new Active war-game. Factory-only. Auto-retires the previous Active for `_squadId`.
   * @param _squadId Non-zero squad key.
   * @param _deployment Deployment record (must have a unique non-zero `topHatId`).
   */
  function register(bytes32 _squadId, INavePirataRegistry.Deployment calldata _deployment) external;

  /**
   * @notice Retire the Active stack for `_squadId` without deploying a replacement. Factory-only.
   * @param _squadId Squad key that currently has an Active stack.
   */
  function retire(bytes32 _squadId) external;

  /*///////////////////////////////////////////////////////////////
                            VIEWS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice The factory authorised to register and retire.
   * @return _factory Factory address.
   */
  function factory() external view returns (address _factory);

  /**
   * @notice Active deployment for `_squadId`, or a zeroed struct if none.
   * @param _squadId Squad key.
   * @return _deployment Nested production deployment of the Active stack.
   */
  function active(bytes32 _squadId) external view returns (INavePirataRegistry.Deployment memory _deployment);

  /**
   * @notice Active tophat id for `_squadId`, or `0` if none.
   * @param _squadId Squad key.
   * @return _topHatId Active tophat id.
   */
  function activeTopHatId(bytes32 _squadId) external view returns (uint256 _topHatId);

  /**
   * @notice Append-only tophat ids for `_squadId`, including the current Active if any.
   * @param _squadId Squad key.
   * @return _topHatIds History in registration order.
   */
  function history(bytes32 _squadId) external view returns (uint256[] memory _topHatIds);

  /**
   * @notice Full record for a tophat, or a zeroed struct if unknown.
   * @param _topHatId Tophat id.
   * @return _record Stored row.
   */
  function record(uint256 _topHatId) external view returns (Record memory _record);

  /**
   * @notice Nested production deployment for a tophat (zeroed if unknown). Same ABI as `INavePirataRegistry.deployment`.
   * @param _topHatId Tophat id.
   * @return _deployment Nested production deployment of that stack.
   */
  function deployment(uint256 _topHatId) external view returns (INavePirataRegistry.Deployment memory _deployment);
}
