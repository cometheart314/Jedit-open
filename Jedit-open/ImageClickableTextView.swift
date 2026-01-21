//
//  ImageClickableTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
//

import Cocoa

// MARK: - ImageClickableTextView

class ImageClickableTextView: NSTextView {

    // MARK: - Properties

    /// Controller for handling image resize operations
    var imageResizeController: ImageResizeController?

    /// Returns whether this document is plain text
    private var isPlainText: Bool {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return false
        }
        return windowController.textDocument?.documentType == .plain
    }

    /// Returns whether substitutions should only apply to rich text
    private var richTextSubstitutionsOnly: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Check if we clicked on an image attachment
        let point = convert(event.locationInWindow, from: nil)

        if let controller = imageResizeController,
           controller.handleClick(in: self, at: point) {
            // Image was clicked, panel is shown, don't pass the event
            return
        }

        // Not an image click, proceed with normal behavior
        super.mouseDown(with: event)
    }

    // MARK: - Spelling and Grammar Menu Actions

    @IBAction override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        UserDefaults.standard.set(isContinuousSpellCheckingEnabled, forKey: UserDefaults.Keys.checkSpellingAsYouType)
    }

    @IBAction override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        UserDefaults.standard.set(isGrammarCheckingEnabled, forKey: UserDefaults.Keys.checkGrammarWithSpelling)
    }

    @IBAction override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        UserDefaults.standard.set(isAutomaticSpellingCorrectionEnabled, forKey: UserDefaults.Keys.correctSpellingAutomatically)
    }

    // MARK: - Substitutions Menu Actions

    @IBAction override func toggleSmartInsertDelete(_ sender: Any?) {
        super.toggleSmartInsertDelete(sender)
        UserDefaults.standard.set(smartInsertDeleteEnabled, forKey: UserDefaults.Keys.smartCopyPaste)
    }

    @IBAction override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        UserDefaults.standard.set(isAutomaticQuoteSubstitutionEnabled, forKey: UserDefaults.Keys.smartQuotes)
    }

    @IBAction override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        UserDefaults.standard.set(isAutomaticDashSubstitutionEnabled, forKey: UserDefaults.Keys.smartDashes)
    }

    @IBAction override func toggleAutomaticLinkDetection(_ sender: Any?) {
        super.toggleAutomaticLinkDetection(sender)
        UserDefaults.standard.set(isAutomaticLinkDetectionEnabled, forKey: UserDefaults.Keys.smartLinks)
    }

    @IBAction override func toggleAutomaticDataDetection(_ sender: Any?) {
        super.toggleAutomaticDataDetection(sender)
        UserDefaults.standard.set(isAutomaticDataDetectionEnabled, forKey: UserDefaults.Keys.dataDetectors)
    }

    @IBAction override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        UserDefaults.standard.set(isAutomaticTextReplacementEnabled, forKey: UserDefaults.Keys.textReplacements)
    }

    // MARK: - Stamp Date/Time Actions

    @IBAction func stampDate(_ sender: Any?) {
        let dateFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.dateFormatType)
        guard let formatType = CalendarDateHelper.DateFormatType(rawValue: dateFormatType) else { return }
        let dateString = formatType.formattedDate()
        insertText(dateString, replacementRange: selectedRange())
    }

    @IBAction func stampTime(_ sender: Any?) {
        let timeFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.timeFormatType)
        guard let formatType = CalendarDateHelper.TimeFormatType(rawValue: timeFormatType) else { return }
        let timeString = formatType.formattedTime()
        insertText(timeString, replacementRange: selectedRange())
    }

    // MARK: - Menu Validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        // Substitution actions that respect "Rich Text Only" setting
        // When "Following Substitutions Enabled Only in Rich Text" is ON and this is plain text,
        // show these items as unchecked (but still enabled)
        if richTextSubstitutionsOnly && isPlainText {
            switch action {
            case #selector(toggleAutomaticQuoteSubstitution(_:)),
                 #selector(toggleAutomaticDashSubstitution(_:)),
                 #selector(toggleAutomaticTextReplacement(_:)),
                 #selector(toggleAutomaticSpellingCorrection(_:)):
                menuItem.state = .off
                return true
            default:
                break
            }
        }

        return super.validateMenuItem(menuItem)
    }
}
