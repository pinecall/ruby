# Contributing

Thanks for reading the code. A patch is welcome, and there is **no CLA**: what you write stays
yours, under the same Apache-2.0 licence as the rest.

## Before you open a pull request

```bash
rake        # the tests, the example's own suite, then `rbs validate`
```

**A change lands with the page that describes it, in the same commit.** A new module or a changed
correspondence with the TypeScript package is a line in `ARCHITECTURE.md`; a new verb or flag is
`README.md` and `docs/the-cli.md`; anything a person writing an agent types is the `docs/` page
for it; anything a user would notice is a line in `CHANGELOG.md` under Unreleased. When a doc and
the code disagree, the code is what happened and the doc is the bug.

## The bar

- Every file opens with one line saying what it is, for whom. 400 lines is the ceiling.
- A comment says *why*, never what the line already says.
- Names are sentences: `visible_declarations`, `refuse_a_name_no_model_can_call`.
- Tests read as sentences too, and assert on behaviour a person would notice.
- No new runtime dependency without a paragraph in the pull request saying what it replaces.

## The wire is generated

Nothing under `lib/pinecall/protocol` exists in this repository: the shapes come from the
`pinecall/protocol` gem, generated from JSON Schema. If a change needs a new field on the wire, it
starts there, with the same field arriving in Python and TypeScript in the same commit.

## Versions

Versions and tags are the maintainer's call. Please do not bump `lib/pinecall/version.rb` in a
pull request — a published version number can never be reused, and picking one by accident burns
it forever.
