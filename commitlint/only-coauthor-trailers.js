// Local commitlint plugin: `only-coauthor-trailers`.
//
// Fails if any line after the commit header is anything other than a blank
// line or a `Co-authored-by: Name <email>` trailer. If anything follows the
// header at all, the second line must be blank (git trailer convention).
const TRAILER = /^Co-authored-by: .+ <.+>$/;

function onlyCoauthorTrailers(parsed) {
  const raw = (parsed.raw || '').replace(/\r\n/g, '\n').replace(/\n+$/, '');
  const lines = raw.split('\n');
  const rest = lines.slice(1);

  if (rest.length === 0) {
    return [true];
  }

  if (rest[0].trim() !== '') {
    return [false, 'the line after the header must be blank; only Co-authored-by trailers may follow'];
  }

  const offenders = rest
    .map((line, i) => ({ line, number: i + 2 }))
    .filter(({ line }) => line.trim() !== '' && !TRAILER.test(line));

  if (offenders.length > 0) {
    const first = offenders[0];
    return [
      false,
      `line ${first.number} is not allowed ("${first.line}"); commits are a single header line, ` +
        'optionally followed by a blank line and Co-authored-by trailers. Put details in the PR description.',
    ];
  }

  return [true];
}

module.exports = {
  rules: {
    'only-coauthor-trailers': onlyCoauthorTrailers,
  },
};
