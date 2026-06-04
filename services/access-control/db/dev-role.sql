-- DEV ONLY: give the gemba_app role a password so the backend can connect over TCP
-- in the local docker setup. In production the app authenticates as gemba_app via
-- your secret store (never a hardcoded password, CLAUDE.md §3). gemba_app is NOT a
-- superuser and has no BYPASSRLS, so Row-Level Security is always enforced for it.
ALTER ROLE gemba_app WITH PASSWORD 'devpassword';
