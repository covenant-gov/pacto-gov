// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TreasuryAuthority} from 'contracts/core/TreasuryAuthority.sol';
import {NavePirataRegistry} from 'contracts/factory/NavePirataRegistry.sol';

import {IntegrationBase} from './IntegrationBase.sol';

/**
 * @title E2ETreasuryAuthorityBase
 * @author Pacto
 * @notice Fork fixtures specific to `TreasuryAuthority` scenarios; shared squad wiring lives on `IntegrationBase`.
 */
abstract contract E2ETreasuryAuthorityBase is IntegrationBase {}

/**
 * @title E2ETreasuryAuthorityTest
 * @author Pacto
 * @notice End-to-end scenarios for `TreasuryAuthority`; function names follow branching in `TreasuryAuthority`
 *         / `ITreasuryAuthority`; empty bodies are intentional for a follow-up pass.
 */
contract E2ETreasuryAuthorityTest is E2ETreasuryAuthorityBase {
  /*///////////////////////////////////////////////////////////////
                        initialize / setUp
  //////////////////////////////////////////////////////////////*/

  function test_e2e_initialize_reverts_whenSafeIsZero() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenProposalExpiryOutOfRange() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenQuorumBpsOutOfRange() public withDeployedNavePirataSquad {}

  function test_e2e_initialize_reverts_whenAlreadyInitialized() public withDeployedNavePirataSquad {}

  function test_e2e_setUp_zodiacShim_appliesInitialization() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        propose
  //////////////////////////////////////////////////////////////*/

  function test_e2e_propose_reverts_whenCallerIsNeitherCaptainNorCrew() public withDeployedNavePirataSquad {}

  function test_e2e_propose_reverts_whenProposerAlreadyHasOpenProposal() public withDeployedNavePirataSquad {}

  function test_e2e_propose_succeeds_whenCallerIsCaptain_recordsState() public withDeployedNavePirataSquad {}

  function test_e2e_propose_succeeds_whenCallerIsCrew_recordsState() public withDeployedNavePirataSquad {}

  function test_e2e_propose_succeeds_reusesProposerSlot_whenPriorProposalExpired() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        crewVote
  //////////////////////////////////////////////////////////////*/

  function test_e2e_crewVote_reverts_whenCallerDoesNotWearCrewHat() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_reverts_whenProposalDoesNotExist() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_reverts_whenProposalExpired() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_reverts_whenCaptainVetoed() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_reverts_whenVoterAlreadyVoted() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_succeeds_incrementsYeas() public withDeployedNavePirataSquad {}

  function test_e2e_crewVote_succeeds_incrementsNays() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        captainVote
  //////////////////////////////////////////////////////////////*/

  function test_e2e_captainVote_reverts_whenCallerDoesNotWearCaptainHat() public withDeployedNavePirataSquad {}

  function test_e2e_captainVote_reverts_whenCaptainAlreadyVoted() public withDeployedNavePirataSquad {}

  function test_e2e_captainVote_reverts_whenProposalExpired() public withDeployedNavePirataSquad {}

  function test_e2e_captainVote_succeeds_whenApproving() public withDeployedNavePirataSquad {}

  function test_e2e_captainVote_succeeds_whenVetoing_defeatsProposalAndClearsOpenSlot()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_captainVote_succeeds_whenVetoing_allowsNewProposeFromSameProposer()
    public
    withDeployedNavePirataSquad
  {}

  /*///////////////////////////////////////////////////////////////
                        execute
  //////////////////////////////////////////////////////////////*/

  function test_e2e_execute_succeeds_call_forwardsToSafeAndClearsOpenSlot() public withDeployedNavePirataSquad {}

  function test_e2e_execute_succeeds_delegatecall_forwardsOperation() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenCrewVoteBelowMajority_majoritySnapshotMode()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_execute_reverts_whenCaptainNotApproved() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenCaptainVetoed() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenSafeExecutionFails() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenAlreadyExecuted() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenProposalExpired() public withDeployedNavePirataSquad {}

  function test_e2e_execute_succeeds_whenQuorumMetAndYeasBeatNays_quorumOfCastMode()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_execute_reverts_whenQuorumNotMet_quorumOfCastMode() public withDeployedNavePirataSquad {}

  function test_e2e_execute_reverts_whenYeasNotGreaterThanNays_quorumOfCastMode() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        parameter setters
  //////////////////////////////////////////////////////////////*/

  function test_e2e_setProposalExpiry_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_setProposalExpiry_reverts_whenNewValueOutOfRange() public withDeployedNavePirataSquad {}

  function test_e2e_setProposalExpiry_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {}

  function test_e2e_setCrewVoteMode_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_setCrewVoteMode_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {}

  function test_e2e_setQuorumBps_reverts_whenCallerDoesNotWearTreasuryAuthorityRoleHat()
    public
    withDeployedNavePirataSquad
  {}

  function test_e2e_setQuorumBps_reverts_whenNewValueOutOfRange() public withDeployedNavePirataSquad {}

  function test_e2e_setQuorumBps_succeeds_whenRoleHolder() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        views / quiescence
  //////////////////////////////////////////////////////////////*/

  function test_e2e_proposal_view_reflectsStoredFields() public withDeployedNavePirataSquad {}

  function test_e2e_hasVoted_reflectsCrewBallots() public withDeployedNavePirataSquad {}

  function test_e2e_openProposalOf_tracksProposerOpenId() public withDeployedNavePirataSquad {}

  function test_e2e_SAFE_matchesSquadSafeAddress() public withDeployedNavePirataSquad {}

  function test_e2e_hatIdGetters_matchDeployment() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_trueOnFreshSquadWhenNoLiveProposalDeadline() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_falseWhileProposalWithinMaxDeadline() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_trueAfterAllProposalsExpired() public withDeployedNavePirataSquad {}

  function test_e2e_isQuiet_falseAgainAfterNewProposal() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        AssetRescuer
  //////////////////////////////////////////////////////////////*/

  function test_e2e_receive_revertsWithRescueDestinationHint() public payable withDeployedNavePirataSquad {}

  function test_e2e_rescueETH_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {}

  function test_e2e_rescueERC20_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {}

  function test_e2e_rescueERC721_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {}

  function test_e2e_rescueERC1155_succeeds_sweepsToSafe() public withDeployedNavePirataSquad {}

  /*///////////////////////////////////////////////////////////////
                        integration wiring
  //////////////////////////////////////////////////////////////*/

  function test_integration_treasuryAuthorityMasterDeployedAndFactoryLive() public view {
    TreasuryAuthority _master = TreasuryAuthority(payable(_masters.treasuryAuthority));
    assertGt(address(_master).code.length, 0);
    assertGt(_infra.navePirataFactory.code.length, 0);
  }

  function test_integration_squadTreasuryMatchesRegistryDeployment() public withDeployedNavePirataSquad {
    assertEq(address(_squadTreasury), NavePirataRegistry(_infra.registry).deployment(_squadTopHatId).treasuryAuthority);
  }
}
