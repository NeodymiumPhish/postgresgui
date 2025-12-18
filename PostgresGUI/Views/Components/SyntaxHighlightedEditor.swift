//
//  SyntaxHighlightedEditor.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import SwiftUI
import AppKit

struct SyntaxHighlightedEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) var colorScheme

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        // Configure text view
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // Set up scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        // Enable ruler view for line numbers
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true

        // Create and set line number ruler
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = lineNumberRuler

        // Set delegate
        textView.delegate = context.coordinator

        // Store reference in coordinator
        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.colorScheme = colorScheme
        context.coordinator.lineNumberRuler = lineNumberRuler

        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        let colorSchemeChanged = context.coordinator.lastColorScheme != colorScheme
        context.coordinator.colorScheme = colorScheme
        context.coordinator.lastColorScheme = colorScheme
        
        // Only update text if it changed from external source (not from user typing)
        // If the user is typing, textDidChange handles the update
        let currentText = textView.string
        if currentText != text && !context.coordinator.isUpdatingFromUserInput {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applySyntaxHighlighting(to: textView, preserveSelection: true)
        } else if colorSchemeChanged {
            // Only re-apply highlighting if color scheme changed
            context.coordinator.applySyntaxHighlighting(to: textView, preserveSelection: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedEditor
        weak var textView: NSTextView?
        weak var lineNumberRuler: LineNumberRulerView?
        var colorScheme: ColorScheme = .light
        var isUpdatingFromUserInput: Bool = false
        var lastColorScheme: ColorScheme = .light
        
        // Cached regex patterns for performance
        private let keywordPattern: NSRegularExpression
        private let stringPattern: NSRegularExpression
        private let numberPattern: NSRegularExpression
        private let singleLineCommentPattern: NSRegularExpression
        private let multiLineCommentPattern: NSRegularExpression
        private let operatorPattern: NSRegularExpression
        private let functionPattern: NSRegularExpression
        
        init(_ parent: SyntaxHighlightedEditor) {
            self.parent = parent
            self.colorScheme = parent.colorScheme
            self.lastColorScheme = parent.colorScheme
            
            // Compile regex patterns
            do {
                // PostgreSQL keywords (case-insensitive)
                keywordPattern = try NSRegularExpression(
                    pattern: "\\b(SELECT|FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|ON|AS|ORDER|BY|GROUP|HAVING|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TABLE|INDEX|VIEW|DATABASE|SCHEMA|UNION|INTERSECT|EXCEPT|DISTINCT|LIMIT|OFFSET|CASE|WHEN|THEN|ELSE|END|IF|EXISTS|NULL|NOT|AND|OR|IN|LIKE|ILIKE|SIMILAR|TO|BETWEEN|IS|CAST|COALESCE|NULLIF|GREATEST|LEAST|EXTRACT|DATE_PART|NOW|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|TRUE|FALSE|BOOLEAN|INTEGER|BIGINT|SMALLINT|DECIMAL|NUMERIC|REAL|DOUBLE|PRECISION|CHAR|VARCHAR|TEXT|BYTEA|DATE|TIME|TIMESTAMP|INTERVAL|ARRAY|JSON|JSONB|UUID|SERIAL|BIGSERIAL|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|CHECK|DEFAULT|CONSTRAINT|USING|WITH|WITHOUT|OIDS|TABLESPACE|STORAGE|PARAMETER|SET|RESET|SHOW|GRANT|REVOKE|EXPLAIN|ANALYZE|VACUUM|REINDEX|CLUSTER|TRUNCATE|BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|TRANSACTION|ISOLATION|LEVEL|READ|WRITE|ONLY|UNCOMMITTED|COMMITTED|REPEATABLE|SERIALIZABLE|LOCK|FOR|UPDATE|SHARE|NOWAIT|SKIP|LOCKED|RETURNING|RETURNS|LANGUAGE|PLPGSQL|FUNCTION|PROCEDURE|TRIGGER|SEQUENCE|TYPE|DOMAIN|ENUM|AGGREGATE|OPERATOR|OPERATOR\\s+CLASS|OPERATOR\\s+FAMILY|RULE|POLICY|EXTENSION|COLLATION|CONVERSION|TEXT\\s+SEARCH|CONFIGURATION|DICTIONARY|PARSER|TEMPLATE|ROLE|USER|GROUP|PASSWORD|SUPERUSER|CREATEDB|CREATEROLE|INHERIT|LOGIN|REPLICATION|BYPASSRLS|CONNECTION\\s+LIMIT|VALID|UNTIL|IN\\s+SCHEMA|PUBLIC|CURRENT_SCHEMA|SEARCH_PATH)\\b",
                    options: [.caseInsensitive]
                )
                
                // Strings: single quotes (handling escaped quotes)
                stringPattern = try NSRegularExpression(
                    pattern: "'(?:[^'\\\\]|\\\\.)*'",
                    options: []
                )
                
                // Numbers: integers and decimals
                numberPattern = try NSRegularExpression(
                    pattern: "\\b\\d+\\.?\\d*\\b",
                    options: []
                )
                
                // Single-line comments
                singleLineCommentPattern = try NSRegularExpression(
                    pattern: "--.*",
                    options: []
                )
                
                // Multi-line comments
                multiLineCommentPattern = try NSRegularExpression(
                    pattern: "/\\*[\\s\\S]*?\\*/",
                    options: [.dotMatchesLineSeparators]
                )
                
                // Operators: PostgreSQL specific operators
                operatorPattern = try NSRegularExpression(
                    pattern: "::|->>|->|@>|<@|\\?\\||\\?&|\\?|<=|>=|<>|!=|[=<>!+\\-*/%&|^~]",
                    options: []
                )
                
                // Functions: identifier followed by opening paren
                functionPattern = try NSRegularExpression(
                    pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*\\(",
                    options: []
                )
            } catch {
                fatalError("Failed to compile regex patterns: \(error)")
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }

            // Mark that we're updating from user input to prevent updateNSView from interfering
            isUpdatingFromUserInput = true

            // Update parent binding immediately
            parent.text = textView.string

            // Apply syntax highlighting incrementally without replacing the entire string
            // This preserves cursor position and doesn't interfere with typing
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let textView = self.textView else { return }
                self.applySyntaxHighlightingIncremental(to: textView)
                // Refresh line numbers
                self.lineNumberRuler?.needsDisplay = true
                // Reset flag after highlighting is applied
                self.isUpdatingFromUserInput = false
            }
        }

        func applySyntaxHighlightingIncremental(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let text = textStorage.string
            guard !text.isEmpty else { return }
            
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            
            // Color scheme colors
            let keywordColor = colorScheme == .dark
                ? NSColor.systemBlue
                : NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
            
            let stringColor = colorScheme == .dark
                ? NSColor.systemGreen
                : NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)
            
            let numberColor = colorScheme == .dark
                ? NSColor.systemOrange
                : NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
            
            let commentColor = colorScheme == .dark
                ? NSColor.systemGray
                : NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            
            let operatorColor = colorScheme == .dark
                ? NSColor.systemPink
                : NSColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1.0)
            
            let functionColor = colorScheme == .dark
                ? NSColor.systemCyan
                : NSColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 1.0)
            
            let defaultColor = NSColor.textColor
            
            // Track ranges that have been highlighted to avoid overlaps
            var highlightedRanges: [NSRange] = []
            
            // Update attributes incrementally instead of replacing the entire string
            // This preserves cursor position and doesn't interfere with typing
            textStorage.beginEditing()
            
            // Ensure font is set
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            textStorage.addAttribute(.font, value: font, range: fullRange)
            
            // Reset all colors to default first
            textStorage.removeAttribute(.foregroundColor, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
            
            // Apply highlighting in order of priority (comments first, then strings, then others)
            
            // 1. Multi-line comments (highest priority)
            multiLineCommentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                textStorage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                highlightedRanges.append(match.range)
            }
            
            // 2. Single-line comments
            singleLineCommentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 3. Strings (high priority)
            stringPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 4. Numbers
            numberPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 5. Keywords
            keywordPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 6. Functions
            functionPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let functionRange = NSRange(location: match.range.location, length: match.range.length - 1)
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, functionRange).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: functionColor, range: functionRange)
                    highlightedRanges.append(functionRange)
                }
            }
            
            // 7. Operators (lowest priority)
            operatorPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    textStorage.addAttribute(.foregroundColor, value: operatorColor, range: match.range)
                }
            }
            
            textStorage.endEditing()
        }
        
        func applySyntaxHighlighting(to textView: NSTextView, preserveSelection: Bool = false) {
            let text = textView.string
            guard !text.isEmpty else { return }
            
            // Save selection range before applying highlighting
            let selectedRange: NSRange
            if preserveSelection {
                let currentRange = textView.selectedRange()
                // Ensure the range is valid for the current text
                let maxLocation = text.utf16.count
                if currentRange.location > maxLocation {
                    selectedRange = NSRange(location: maxLocation, length: 0)
                } else {
                    selectedRange = currentRange
                }
            } else {
                selectedRange = NSRange(location: text.utf16.count, length: 0)
            }
            
            let attributedString = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            
            // Set default font and color
            let defaultColor = colorScheme == .dark 
                ? NSColor.textColor 
                : NSColor.textColor
            attributedString.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
            attributedString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular), range: fullRange)
            
            // Color scheme colors
            let keywordColor = colorScheme == .dark
                ? NSColor.systemBlue
                : NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
            
            let stringColor = colorScheme == .dark
                ? NSColor.systemGreen
                : NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0)
            
            let numberColor = colorScheme == .dark
                ? NSColor.systemOrange
                : NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
            
            let commentColor = colorScheme == .dark
                ? NSColor.systemGray
                : NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            
            let operatorColor = colorScheme == .dark
                ? NSColor.systemPink
                : NSColor(red: 0.8, green: 0.0, blue: 0.4, alpha: 1.0)
            
            let functionColor = colorScheme == .dark
                ? NSColor.systemCyan
                : NSColor(red: 0.0, green: 0.5, blue: 0.8, alpha: 1.0)
            
            // Track ranges that have been highlighted to avoid overlaps
            var highlightedRanges: [NSRange] = []
            
            // Apply highlighting in order of priority (comments first, then strings, then others)
            
            // 1. Multi-line comments (highest priority)
            multiLineCommentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                highlightedRanges.append(match.range)
            }
            
            // 2. Single-line comments
            singleLineCommentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Check if this range overlaps with a multi-line comment
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: commentColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 3. Strings (high priority)
            stringPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Check if this range overlaps with a comment
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: stringColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 4. Numbers
            numberPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Check if this range overlaps with comments or strings
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: numberColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 5. Keywords
            keywordPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Check if this range overlaps with comments or strings
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: keywordColor, range: match.range)
                    highlightedRanges.append(match.range)
                }
            }
            
            // 6. Functions
            functionPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Only highlight the function name part (before the opening paren)
                let functionRange = NSRange(location: match.range.location, length: match.range.length - 1)
                // Check if this range overlaps with comments or strings
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, functionRange).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: functionColor, range: functionRange)
                    highlightedRanges.append(functionRange)
                }
            }
            
            // 7. Operators (lowest priority, but don't override comments/strings)
            operatorPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Check if this range overlaps with comments or strings
                if !highlightedRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    attributedString.addAttribute(.foregroundColor, value: operatorColor, range: match.range)
                }
            }
            
            // Apply the attributed string while preserving selection
            let textStorage = textView.textStorage
            let wasFirstResponder = textView.window?.firstResponder === textView
            
            textStorage?.beginEditing()
            textStorage?.setAttributedString(attributedString)
            textStorage?.endEditing()
            
            // Restore selection if we were preserving it
            if preserveSelection {
                // Ensure the selected range is valid for the new text
                let maxLocation = text.utf16.count
                let validLocation = min(selectedRange.location, maxLocation)
                let validLength = min(selectedRange.length, maxLocation - validLocation)
                let validRange = NSRange(location: validLocation, length: validLength)
                
                // Restore selection on the next run loop to ensure text storage update is complete
                DispatchQueue.main.async {
                    textView.setSelectedRange(validRange)
                    // Ensure text view remains first responder if it was before
                    if wasFirstResponder {
                        textView.window?.makeFirstResponder(textView)
                    }
                }
            }
        }
    }
}

// MARK: - Line Number Ruler View

class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView.enclosingScrollView?.documentView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Background color
        let backgroundColor = NSColor.controlBackgroundColor
        backgroundColor.setFill()
        context.fill(bounds)

        // Draw separator line
        let separatorColor = NSColor.separatorColor
        separatorColor.setStroke()
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        context.addLine(to: CGPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        context.strokePath()

        // Get visible rect
        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? .zero

        // Get text layout manager
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string

        // Draw line numbers for visible lines (same font as editor)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Handle empty text case - show line number 1 and 2
        if text.isEmpty {
            // Get the default line height
            let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let lineHeight = layoutManager.defaultLineHeight(for: font)

            // Draw line 1
            let lineNumberString1 = "1" as NSString
            let stringSize1 = lineNumberString1.size(withAttributes: textAttributes)
            let drawPoint1 = NSPoint(
                x: bounds.width - stringSize1.width - 8,
                y: textView.textContainerInset.height
            )
            lineNumberString1.draw(at: drawPoint1, withAttributes: textAttributes)

            // Draw line 2 (next line)
            let lineNumberString2 = "2" as NSString
            let stringSize2 = lineNumberString2.size(withAttributes: textAttributes)
            let drawPoint2 = NSPoint(
                x: bounds.width - stringSize2.width - 8,
                y: textView.textContainerInset.height + lineHeight
            )
            lineNumberString2.draw(at: drawPoint2, withAttributes: textAttributes)
            return
        }

        // Calculate line numbers to display
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count lines up to the start of visible range
        var lineNumber = 1
        var index = 0
        while index < characterRange.location {
            if (text as NSString).character(at: index) == 0x0A { // newline
                lineNumber += 1
            }
            index += 1
        }

        var currentIndex = characterRange.location
        var lastYPosition: CGFloat = 0
        var lastLineHeight: CGFloat = 0
        var lastLineNumber = lineNumber

        while currentIndex <= text.count {
            // Handle the case where we're at the end of text
            let charLength = (currentIndex < text.count) ? 1 : 0

            // Get the glyph range for this line
            let lineGlyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: currentIndex, length: charLength),
                actualCharacterRange: nil
            )

            // Get the bounding rect for this line
            let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)

            // Adjust for text view insets and scroll position
            let yPosition = lineRect.minY + textView.textContainerInset.height - visibleRect.minY

            // Store the last y position and line height for drawing the next line number
            lastYPosition = yPosition
            if lineRect.height > 0 {
                lastLineHeight = lineRect.height
            }

            // Draw line number
            let lineNumberString = "\(lineNumber)" as NSString
            let stringSize = lineNumberString.size(withAttributes: textAttributes)

            let drawPoint = NSPoint(
                x: bounds.width - stringSize.width - 8,
                y: yPosition
            )
            lineNumberString.draw(at: drawPoint, withAttributes: textAttributes)

            // Store the last line number we drew
            lastLineNumber = lineNumber

            // Move to next line
            lineNumber += 1

            // Find the next newline
            var foundNewline = false
            while currentIndex < text.count {
                if (text as NSString).character(at: currentIndex) == 0x0A {
                    currentIndex += 1
                    foundNewline = true
                    break
                }
                currentIndex += 1
            }

            // If we didn't find a newline, we're at the end
            if !foundNewline {
                break
            }

            // Check if we've gone beyond the visible range
            if currentIndex > NSMaxRange(characterRange) {
                break
            }
        }

        // Draw the next line number after the last line
        if lastLineHeight > 0 {
            let nextYPosition = lastYPosition + lastLineHeight
            let nextLineNumberString = "\(lastLineNumber + 1)" as NSString
            let stringSize = nextLineNumberString.size(withAttributes: textAttributes)
            let drawPoint = NSPoint(
                x: bounds.width - stringSize.width - 8,
                y: nextYPosition
            )
            nextLineNumberString.draw(at: drawPoint, withAttributes: textAttributes)
        }
    }
}

