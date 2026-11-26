# Codex desktop approvals in the notch

## Agreed behavior

- Add a separate Codex desktop approvals switch in CatNotch Settings, off by default.
- Give each request 30 seconds from arrival, including time spent in the queue. At expiry, remove it from the queue and return the decision to Codex for its normal approval prompt. Expiry never grants approval.
- When a Codex desktop chat needs approval for a command or file change, reuse the notch request strip. Show the project, chat, and proposed command or affected files.
- Show the strip while the user is in another app or another chat. When the requesting chat is visible, let Codex present its own prompt.
- Offer **Approve once**, **Decline**, and **Open in Codex**. Opening the chat hands the pending decision to Codex.
- Show pending requests oldest first with a count such as **1 of 3**. Clear each resolved request, including one answered in Codex.
- A notification-only version is acceptable if it can open the exact chat awaiting approval.

## Desktop verification before implementation

Use an isolated configuration to verify desktop hook delivery and decision handling for commands and file changes. Verify how to identify the visible chat, open the requesting chat, and clear interrupted or resolved requests. The [Codex hook reference](https://developers.openai.com/codex/hooks) documents that the normal approval flow starts after the hook yields its decision.
