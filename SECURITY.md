# Security and private data

## Current scope

My City is a local single-player prototype. Godot owns the save; the optional Worker queries external providers. Its development token is shared between that client and its local service: **it is not an account or authorization system for a public hosted game**.

The default configuration listens on `127.0.0.1:8787`, without remote deployment. Public source code does not publish the service or grant access to provider accounts. Never distribute your service token inside an executable, export, or URL.

## Keep out of the repository

- `.env`, `.dev.vars`, and variants containing real values; only empty templates should be shared.
- Provider keys, development tokens, private keys, and cookies.
- Personal saves, conversation transcripts, request dumps, and logs containing player context.
- Exports, captures, or infrastructure links containing credentials or private information.

`.gitignore` prevents common accidental additions; it does not remove files already in Git. Before publishing, inspect history, branches, tags, attachments, and automation logs as well. Use a protected commit email when a personal address should remain private.

## Trust boundaries

The client sends only context the speaking character is allowed to know. Another character's biography, private memory, or unauthorized secret must not enter the model payload. Confirmed dialogue can remain in the local save; partial or cancelled output is discarded.

The backend validates input, requires Bearer authentication, rejects web origins, bounds payloads and deadlines, and does not follow redirects to another provider. These controls do not make it a production backend. A shared deployment needs user identity, per-save authorization, usage quotas, and authoritative state. A model response never authorizes a reward or world mutation.

Ordinary tests use fake credentials and mocked responses. Do not reuse a real key in a fixture or attach request bodies without reviewing their contents.

## Report a problem

For ordinary game bugs, provide reproduction steps using synthetic data. For vulnerabilities, do not post secrets or exploit evidence containing real information in an issue.

If **Security → Report a vulnerability** is enabled for the repository, use that private channel. If unavailable, ask the maintainer for a private channel without posting sensitive details publicly. No bounty program or response-time commitment is implied.

If a credential is accidentally published, revoke or rotate it with the provider. Removing its latest file does not invalidate copies or older revisions. Then review affected history and logs. Do not reproduce the compromised value when documenting the incident.
