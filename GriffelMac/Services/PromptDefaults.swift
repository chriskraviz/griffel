import Foundation

/// The built-in text of every editable feature prompt, in one place.
///
/// `TextGenerationService` and the Prompts editor both read from here, so the
/// editor always shows exactly the text that would run. A stored prompt that is
/// empty means "use the default" rather than a copy of it — that way a user who
/// never edited a prompt keeps picking up improvements to it.
enum PromptDefaults {
    /// Griffel+ with Bearbeitungsgrad *Korrektur*.
    static let korrektur = """
    Du erhaeltst ein gesprochenes Transkript. Korrigiere Rechtschreibung, Grammatik \
    und Zeichensetzung, entferne Fuellwoerter und offensichtliche Versprecher. \
    Behalte Bedeutung, Ton und Sprache exakt bei. \
    Gib NUR den ueberarbeiteten Text zurueck, keine Erklaerungen.
    """

    /// Griffel+ with Bearbeitungsgrad *Lektorat*. The tone line from
    /// `TextImprovementSettings.tone` is appended to whatever stands here.
    static let lektorat = """
    Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
    - Korrigiere Rechtschreibung und Grammatik
    - Verbessere die Formulierung und den Lesefluss
    - Behalte die urspruengliche Bedeutung bei
    - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
    """

    /// Auswahl bearbeiten. The spoken instruction and the selected text are
    /// appended as the user message, not here.
    static let selectionEdit = """
    Du bist ein praeziser Textbearbeiter. Wende die gesprochene Anweisung auf den markierten Text an. \
    Behalte Sprache, Format und Zeilenumbrueche bei, soweit die Anweisung nichts anderes verlangt. \
    Gib NUR den bearbeiteten Text zurueck, keine Erklaerungen.
    """

    /// Braindump *Ordnen*.
    static let braindump = """
    Du erhaeltst gesprochene, unsortierte Gedanken (je Zeile ein Eintrag mit Zeitstempel). \
    Ordne sie in genau diese drei Markdown-Abschnitte: \
    ## Zusammenfassung (2-4 Saetze), ## Aufgaben (Checkliste mit - [ ]), ## Ideen (Stichpunkte). \
    Fasse Doppelungen zusammen, erfinde nichts dazu und bleibe auf Deutsch. \
    Gib NUR das Markdown zurueck, keine Erklaerungen.
    """

    /// Appended to every feature prompt, but only when the run resolves to the
    /// on-device model. Small 4-bit models paraphrase and compress more freely
    /// than GPT-4o does, which is wrong for Korrektur in particular — this pulls
    /// them back without making the remote prompts read as nagging.
    static let localAddendum = """
    Lasse keine inhaltlichen Angaben weg und erfinde nichts dazu.
    """
}
