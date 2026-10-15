// Commit message rules for jwall-engineering repos.
//
// A commit message is a single-line Conventional Commit header of at most 100
// characters. The only content allowed after the header is a blank line
// followed by `Co-authored-by: Name <email>` trailers. Details belong in the
// PR description, not the commit body.
const onlyCoauthorTrailers = require('./commitlint/only-coauthor-trailers');

module.exports = {
  extends: ['@commitlint/config-conventional'],
  plugins: [onlyCoauthorTrailers],
  // Do not silently skip merge/fixup/revert messages: history is linear and
  // every commit on main must be a Conventional Commit.
  defaultIgnores: false,
  rules: {
    'header-max-length': [2, 'always', 100],
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'docs', 'chore', 'refactor', 'ci', 'build', 'perf', 'style', 'test', 'revert'],
    ],
    // The local plugin owns everything after the header; disable the built-in
    // body/footer length rules so they never mask or duplicate its message.
    'body-max-line-length': [0],
    'footer-max-line-length': [0],
    'only-coauthor-trailers': [2, 'always'],
  },
};
