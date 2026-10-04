.pragma library

// Small arithmetic evaluator for the launcher: numbers, + - * / % ^,
// parentheses, unary minus, pi, e and a few functions. A hand-written parser
// rather than eval(), so typed text is never run as code.
// evaluate(text) returns a number, or null if the text is not a complete
// expression.

const functions = {
    sqrt: Math.sqrt,
    abs: Math.abs,
    round: Math.round,
    floor: Math.floor,
    ceil: Math.ceil,
    sin: Math.sin,
    cos: Math.cos,
    tan: Math.tan,
    ln: Math.log,
    log: Math.log10
};

const constants = {
    pi: Math.PI,
    e: Math.E
};

function tokenize(text) {
    const tokens = [];
    let rest = text.trim();
    while (rest.length > 0) {
        // no sticky regex: match at the start of what is left, then cut it off
        let match = /^(\d+(?:[.,]\d+)?|[.,]\d+)/.exec(rest);
        if (match) {
            tokens.push({ type: "number", value: parseFloat(match[1].replace(",", ".")) });
        } else if ((match = /^[a-z]+/.exec(rest))) {
            tokens.push({ type: "name", value: match[0] });
        } else if ((match = /^[-+*\/%^()]/.exec(rest))) {
            tokens.push({ type: "op", value: match[0] });
        } else {
            return null;
        }
        rest = rest.slice(match[0].length).trim();
    }
    return tokens;
}

function evaluate(text) {
    const tokens = tokenize(text.toLowerCase());
    if (!tokens || tokens.length === 0)
        return null;
    let index = 0;

    function peek(value) {
        return index < tokens.length && tokens[index].type === "op" && tokens[index].value === value;
    }

    // expression := term (("+" | "-") term)*
    function expression() {
        let value = term();
        while (peek("+") || peek("-")) {
            const op = tokens[index++].value;
            const right = term();
            value = op === "+" ? value + right : value - right;
        }
        return value;
    }

    // term := factor (("*" | "/" | "%") factor)*
    function term() {
        let value = factor();
        while (peek("*") || peek("/") || peek("%")) {
            const op = tokens[index++].value;
            const right = factor();
            value = op === "*" ? value * right : op === "/" ? value / right : value % right;
        }
        return value;
    }

    // factor := ("-" | "+") factor | power
    function factor() {
        if (peek("-")) {
            index++;
            return -factor();
        }
        if (peek("+")) {
            index++;
            return factor();
        }
        return power();
    }

    // power := atom ("^" factor)?   (right associative)
    function power() {
        const base = atom();
        if (peek("^")) {
            index++;
            return Math.pow(base, factor());
        }
        return base;
    }

    function atom() {
        const token = tokens[index++];
        if (!token)
            throw new Error("unexpected end");
        if (token.type === "number")
            return token.value;
        if (token.type === "name") {
            if (token.value in constants)
                return constants[token.value];
            if (token.value in functions && peek("(")) {
                index++;
                const argument = expression();
                if (!peek(")"))
                    throw new Error("expected )");
                index++;
                return functions[token.value](argument);
            }
            throw new Error("unknown name");
        }
        if (token.value === "(") {
            const value = expression();
            if (!peek(")"))
                throw new Error("expected )");
            index++;
            return value;
        }
        throw new Error("unexpected token");
    }

    try {
        const value = expression();
        if (index !== tokens.length || !isFinite(value))
            return null;
        return value;
    } catch (error) {
        return null;
    }
}

// True for text worth showing a result for without the "=" prefix: it has
// an operator or a function call, so a bare number or a word is not hijacked.
function looksLikeMath(text) {
    return /^[\s\d.,()+\-*\/%^a-z]+$/i.test(text) && /\d/.test(text) && /[+\-*\/%^(]/.test(text.trim().slice(1));
}

function format(value) {
    // trim floating-point noise such as 0.30000000000000004
    return String(parseFloat(value.toPrecision(12)));
}
