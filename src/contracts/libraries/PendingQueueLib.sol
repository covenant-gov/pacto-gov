// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title PendingQueueLib
 * @author Pacto
 * @notice 1-based indexed queue of `(account, eta)` with O(1) enqueue / dequeue
 */
library PendingQueueLib {
  /**
   * @notice One queued account and its executable-at timestamp.
   * @param account Queued address.
   * @param eta Unix timestamp when the entry becomes executable.
   */
  struct Entry {
    address account;
    uint64 eta;
  }

  /**
   * @notice `account` is not present in the queue.
   * @param account Address whose pending entry was expected but missing.
   */
  error PendingQueueLib_NotPending(address account);

  /**
   * @notice Push `account` or overwrite `eta` if already queued.
   * @param list Entry array.
   * @param indexOf 1-based index map (`0` means absent).
   * @param account Address to enqueue.
   * @param eta New executable-at timestamp.
   */
  function enqueue(
    Entry[] storage list,
    mapping(address => uint256) storage indexOf,
    address account,
    uint64 eta
  ) internal {
    uint256 i = indexOf[account];
    if (i == 0) {
      list.push(Entry({account: account, eta: eta}));
      indexOf[account] = list.length;
    } else {
      list[i - 1].eta = eta;
    }
  }

  /**
   * @notice Swap-and-pop `account` from `list`. Reverts if absent.
   * @param list Entry array.
   * @param indexOf 1-based index map.
   * @param account Address to remove.
   */
  function dequeue(Entry[] storage list, mapping(address => uint256) storage indexOf, address account) internal {
    uint256 i = indexOf[account];
    if (i == 0) revert PendingQueueLib_NotPending(account);
    uint256 last = list.length;
    if (i != last) {
      Entry storage moved = list[last - 1];
      list[i - 1] = moved;
      indexOf[moved.account] = i;
    }
    list.pop();
    delete indexOf[account];
  }

  /**
   * @notice Executable-at timestamp for `account`, or zero if not queued.
   * @param list Entry array.
   * @param indexOf 1-based index map.
   * @param account Address to look up.
   * @return eta Timestamp, or zero.
   */
  function etaOf(
    Entry[] storage list,
    mapping(address => uint256) storage indexOf,
    address account
  ) internal view returns (uint256 eta) {
    uint256 i = indexOf[account];
    if (i != 0) eta = list[i - 1].eta;
  }
}
