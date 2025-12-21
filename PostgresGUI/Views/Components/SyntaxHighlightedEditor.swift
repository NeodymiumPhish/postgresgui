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


