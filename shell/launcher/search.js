.pragma library

// Ranking of applications against a typed query.

// How well `query` matches `text` (both lower case): 0 = not at all.
function match(text, query) {
    if (!text)
        return 0;
    if (text === query)
        return 100;
    if (text.startsWith(query))
        return 90;
    // at the start of a later word: "code" in "visual studio code"
    const at = text.indexOf(query);
    if (at > 0 && /[\s\-_.\/(]/.test(text[at - 1]))
        return 75;
    // initials: "vsc" for "visual studio code"
    const initials = text.split(/[\s\-_.]+/).map(word => word[0] ?? "").join("");
    if (query.length >= 2 && initials.startsWith(query))
        return 70;
    if (at > 0)
        return 60;
    // letters in order with gaps: "frfx" for "firefox"
    if (query.length >= 3) {
        let position = 0, gaps = 0;
        for (const letter of query) {
            const found = text.indexOf(letter, position);
            if (found < 0)
                return 0;
            gaps += found - position;
            position = found + 1;
        }
        return Math.max(5, 40 - gaps * 2);
    }
    return 0;
}

// Score of one application for one query word, across its fields. The name
// counts fully, descriptive fields less.
function scoreWord(fields, word) {
    return Math.max(match(fields.name, word), match(fields.generic, word) * 0.7, match(fields.keywords, word) * 0.5, match(fields.id, word) * 0.45, match(fields.comment, word) * 0.3);
}

// Every word of the query must match somewhere.
function score(fields, words) {
    let total = 0;
    for (const word of words) {
        const s = scoreWord(fields, word);
        if (s <= 0)
            return 0;
        total += s;
    }
    return total / words.length;
}
