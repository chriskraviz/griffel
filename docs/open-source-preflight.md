# Open Source Preflight

Use this checklist before making the repository public.

## P0 Before Public

- Run a local build with `./build.sh --debug`.
- Run a secret scan across the working tree and commit history.
- Confirm there are no private URLs, hosted backend credentials, internal docs, or old project references.
- Keep the repository private until another maintainer has reviewed the first public commit.
- Confirm the root `LICENSE`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, and `SUPPORT.md` are present.
- Make the preview status explicit: experimental, bring your own OpenAI API key, no hosted backend, no warranty.
- Enable Dependabot alerts and Dependabot security updates.
- Keep GitHub Actions permissions read-only by default.
- Set the repository topics.

## P0 Immediately After Public

GitHub gates the remaining security settings behind a paid plan **or** a public
repository. On a free plan they cannot be switched on while the repo is still
private — the API answers `Secret scanning is not available for this
repository`, `Fork PR approval is not allowed for private repositories`, or
`Upgrade to GitHub Pro or make this repository public`. So they are not a
before-the-flip step; they are the first thing to do right after it, in the
same sitting:

- Enable secret scanning and push protection.
- Enable private vulnerability reporting.
- Require approval for workflows from first-time contributors.
- Protect `main`: require a pull request, require the `Build macOS app` check,
  block force pushes and deletions. Requiring an approving review only works
  once a second maintainer exists — GitHub does not let you approve your own
  pull request, so a solo maintainer must leave the count at zero or keep an
  admin bypass.

## P1 Soon After Public

- Decide whether Issues alone are enough or whether Discussions should be enabled for questions.
- Add a lightweight release process only after the build is signed and notarized.
- Add basic tests once provider boundaries are extracted.

## P2 Later

- Keep CODEOWNERS current — an entry naming someone who is not a collaborator of the public repository silently does nothing.
- Add local model cleanup after the in-app download/install flow.
- Consider CodeQL once the repo has enough surface area to justify scheduled scans.
- Add signed and notarized release artifacts for non-developer testers.
