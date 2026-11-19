import ExhibitCore

/// The words the grammar knows. Everything outside them makes it decline, so a model can try.
enum GrammarLexicon {
    /// Verb phrases, longest first so "put an arrow on" wins over "put".
    static let verbs: [(words: [String], mark: MarkKind)] = {
        let table: [(String, MarkKind)] = [
            ("blur", .blur), ("hide", .blur), ("redact", .blur), ("censor", .blur), ("obscure", .blur),
            ("mask", .blur), ("black out", .blur), ("blank out", .blur), ("pixelate", .blur),
            ("highlight", .highlight),
            ("circle", .circle), ("ring", .circle), ("draw a circle around", .circle), ("put a circle around", .circle),
            ("box", .box), ("outline", .box), ("frame", .box), ("draw a box around", .box), ("put a box around", .box),
            ("point at", .arrow), ("point to", .arrow), ("point out", .arrow), ("arrow", .arrow),
            // Dictation mis-hearings of "point at" seen in the spike: "Point it open tickets", "Appointed update plan".
            ("point it at", .arrow), ("point it to", .arrow), ("point it", .arrow), ("appointed", .arrow),
            ("pointed at", .arrow), ("pointed to", .arrow),
            ("put an arrow", .arrow), ("add an arrow", .arrow), ("draw an arrow", .arrow),
            ("label", .text), ("add a label", .text), ("write", .text),
            ("number", .step), ("step", .step), ("add steps to", .step)
        ]
        return table.map { (Words.of($0.0), $0.1) }.sorted { $0.words.count > $1.words.count }
    }()

    /// Said before the verb and meaningless: "please", "can you".
    static let fillers: Set<String> = ["please", "can", "could", "would", "you", "now", "ok", "okay", "um", "uh",
                                       "and", "then", "also", "just", "go", "ahead", "so"]

    static let conjunctions: Set<String> = ["and", "then", "also", "plus"]

    /// Prepositions between a verb and its object: "point at", "arrow to", "circle around".
    static let prepositions: Set<String> = ["on", "at", "to", "around", "over", "onto", "the", "next", "by"]

    static let determiners: Set<String> = ["the", "a", "an", "my", "our", "your", "their", "his", "her", "its", "of",
                                           "both", "these", "those"]
    /// Determiners that tie a thing to someone: "her email" is one person's, not every email.
    static let possessives: Set<String> = ["my", "our", "your", "their", "his", "her", "its"]
    static let everyWords: Set<String> = ["all", "every", "each", "any"]

    /// UI words after the thing itself: "the reply button". Dropped before matching.
    static let uiNouns: Set<String> = ["button", "buttons", "link", "links", "field", "fields", "heading", "headings",
                                       "title", "tab", "tabs", "column", "columns", "section", "icon", "icons",
                                       "menu", "option", "item", "items", "entry", "entries", "label"]

    /// UI nouns that name a control: "the export button" is a short run of text on its own, not the word "export"
    /// inside a sentence or a line of code.
    static let controlNouns: Set<String> = ["button", "buttons", "link", "links", "tab", "tabs", "menu", "icon",
                                            "icons", "option"]

    static let deictic: [[String]] = [["this"], ["that"], ["here"], ["it"], ["there"], ["this", "one"],
                                      ["that", "one"], ["this", "bit"], ["this", "part"]]

    /// Words that mean the request needs judgement, not lookup.
    static let judgement: Set<String> = ["anything", "everything", "whatever", "identifies", "identify",
                                         "identifying", "about", "related", "mentions", "mentioning", "most",
                                         "least", "personal", "private", "important"]
    /// Relative words that start a description ("the commit that fixed ..."), unless they end the clause.
    static let relatives: Set<String> = ["that", "which", "who", "whose"]

    static let colors: Set<String> = ["red", "yellow", "blue", "green"]

    /// Phrases naming a sensitive kind.
    static let kinds: [(words: [String], kinds: [TargetKind])] = {
        let table: [(String, [TargetKind])] = [
            ("email", [.email]), ("emails", [.email]), ("email address", [.email]), ("address", [.email]),
            ("emails address", [.email]), ("mail", [.email]),
            ("key", [.key]), ("api key", [.key]), ("token", [.key]), ("api token", [.key]), ("password", [.key]),
            ("secret", [.key]), ("access key", [.key]), ("access token", [.key]),
            ("card", [.card]), ("card number", [.card]), ("credit card", [.card]), ("credit card number", [.card]),
            ("phone", [.phone]), ("phone number", [.phone]), ("telephone number", [.phone]),
            ("face", [.face]), ("faces", [.face]),
            ("sensitive", [.email, .key, .card, .phone]), ("sensitive info", [.email, .key, .card, .phone]),
            ("sensitive data", [.email, .key, .card, .phone]), ("sensitive stuff", [.email, .key, .card, .phone])
        ]
        return table.map { (Words.of($0.0), $0.1) }
    }()

    static let kindWords: Set<String> = Set(kinds.flatMap(\.words))

    static let ordinals: Set<String> = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "to", "too", "for"]
}
