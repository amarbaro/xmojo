# Security

Report vulnerabilities privately to dev@amarbaro.com. Do not open a public issue for a security problem.

You will get an acknowledgement within 7 days. Fixed issues are noted in `CHANGELOG.md` with credit if you want it.

Scope: xmojo parses untrusted input. A crash, an abort, or memory or time out of proportion to the input on crafted XML is in scope. xmojo does not process DTDs, so entity-expansion attacks ("billion laughs") have no entry point; a way around that is in scope too.
