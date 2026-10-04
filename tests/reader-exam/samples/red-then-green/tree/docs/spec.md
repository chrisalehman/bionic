# Spec — landing reads the stamps

**REQ-1.** A branch lands only when the suites run at its head passed.

- **AC-1.1.** A branch whose checkout has a failing suite run at its head is refused, and
  the refusal says why. Fails when: a red suite at the head lands.
- **AC-1.2.** A branch with no suite run at all is refused.
