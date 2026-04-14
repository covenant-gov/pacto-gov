// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IQuartermaster
 * @author Pacto
 * @notice Timelocked crew onboarding and offboarding for the Nave Pirata template; admin of the crew hat in Hats Protocol.
 * @dev The captain requests adds/removes; execution happens after `CREW_CHANGE_DELAY`. While a mutiny is active, onboarding is blocked.
 *      Mutiny-only hooks mint or hand off crew without delay. Does not import Hats types so this interface stays toolchain-stable.
 */
interface IQuartermaster {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A crew add was scheduled by the captain
   * @param _candidate Address that may receive the crew hat after the delay
   * @param _executableAt Timestamp when `executeAddCrew` becomes valid
   */
  event CrewAddScheduled(address indexed _candidate, uint256 _executableAt);

  /**
   * @notice A crew removal was scheduled by the captain
   * @param _crew Address whose crew hat may be burned after the delay
   * @param _executableAt Timestamp when `executeRemoveCrew` becomes valid
   */
  event CrewRemoveScheduled(address indexed _crew, uint256 _executableAt);

  /**
   * @notice A scheduled crew add was executed
   * @param _candidate Address that received the crew hat
   */
  event CrewAddExecuted(address indexed _candidate);

  /**
   * @notice A scheduled crew removal was executed
   * @param _crew Address that lost the crew hat
   */
  event CrewRemoveExecuted(address indexed _crew);

  /**
   * @notice Mutiny mode toggled (disables captain-driven onboarding while active)
   * @param _active True when a mutiny is in progress
   */
  event MutinyActiveSet(bool _active);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Only the current captain wearer may call
   */
  error Quartermaster_OnlyCaptain();

  /**
   * @notice Only the mutiny module may call
   */
  error Quartermaster_OnlyMutinyModule();

  /**
   * @notice Crew onboarding is blocked while mutiny is active
   */
  error Quartermaster_MutinyActive();

  /**
   * @notice No pending operation or delay not elapsed
   */
  error Quartermaster_NotExecutable();

  /**
   * @notice Candidate is invalid or cannot receive crew (e.g. is current captain wearer)
   */
  error Quartermaster_InvalidCandidate();

  /**
   * @notice Crew hat supply cap reached
   */
  error Quartermaster_CrewHatMaxSupply();

  /**
   * @notice Operation not found or already cleared
   */
  error Quartermaster_NoPendingOperation();

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Schedule minting the crew hat to `_candidate` after `CREW_CHANGE_DELAY`
   * @dev Reverts if mutiny active or candidate cannot be crew
   * @param _candidate Address to receive the crew hat
   */
  function requestAddCrew(address _candidate) external;

  /**
   * @notice Schedule burning the crew hat from `_crew` after `CREW_CHANGE_DELAY`
   * @dev Reverts if mutiny active
   * @param _crew Address to remove from crew
   */
  function requestRemoveCrew(address _crew) external;

  /**
   * @notice Execute a scheduled crew add after the delay
   * @param _candidate The same address passed to `requestAddCrew`
   */
  function executeAddCrew(address _candidate) external;

  /**
   * @notice Execute a scheduled crew removal after the delay
   * @param _crew The same address passed to `requestRemoveCrew`
   */
  function executeRemoveCrew(address _crew) external;

  /**
   * @notice Mint one crew hat to `_to` with no delay (mutiny / succession path)
   * @dev Only callable by the mutiny module (`MUTINY_MODULE()`); used e.g. to seat a deposed human captain as crew
   * @param _to Recipient who must not be the current captain wearer
   */
  function mintCrewFromMutiny(address _to) external;

  /**
   * @notice Hand crew from elected successor to former captain in one mutiny step (EOA → EOA)
   * @dev Only callable by the mutiny module (`MUTINY_MODULE()`); burns crew from `_newCaptain` if present and mints to `_formerCaptain`
   * @param _formerCaptain Previous captain (receives crew)
   * @param _newCaptain New captain (must not retain crew hat after execution)
   */
  function crewHandoffForMutiny(address _formerCaptain, address _newCaptain) external;

  /**
   * @notice Toggle mutiny mode for onboarding guards
   * @dev Only callable by the mutiny module (`MUTINY_MODULE()`)
   * @param _active True to block captain onboarding
   */
  function setMutinyActive(bool _active) external;

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Hats Protocol singleton used for mint/burn/reads
   * @return _hats The Hats contract address
   */
  function HATS() external view returns (address _hats);

  /**
   * @notice ERC1155-style id of the crew hat this contract administers
   * @return _crewHatId The crew hat id
   */
  function CREW_HAT_ID() external view returns (uint256 _crewHatId);

  /**
   * @notice ERC1155-style id of the captain hat (for captain-only checks)
   * @return _captainHatId The captain hat id
   */
  function CAPTAIN_HAT_ID() external view returns (uint256 _captainHatId);

  /**
   * @notice Delay in seconds between scheduling and executing crew add/remove
   * @return _delay The delay
   */
  function CREW_CHANGE_DELAY() external view returns (uint256 _delay);

  /**
   * @notice Module allowed to call mutiny-only hooks and `setMutinyActive`
   * @return _module The mutiny module address
   */
  function MUTINY_MODULE() external view returns (address _module);

  /**
   * @notice Whether a mutiny is active (captain cannot onboard new crew)
   * @return _active True if mutiny is active
   */
  function mutinyActive() external view returns (bool _active);

  /**
   * @notice Timestamp after which `executeAddCrew` succeeds, or zero if none
   * @param _candidate The candidate address
   * @return _executableAt Unix timestamp, or 0
   */
  function pendingCrewAddAt(address _candidate) external view returns (uint256 _executableAt);

  /**
   * @notice Timestamp after which `executeRemoveCrew` succeeds, or zero if none
   * @param _crew The crew address
   * @return _executableAt Unix timestamp, or 0
   */
  function pendingCrewRemoveAt(address _crew) external view returns (uint256 _executableAt);
}
