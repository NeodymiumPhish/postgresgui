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
        
        // Set delegate
        textView.delegate = context.coordinator
        
        // Store reference in coordinator
        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.colorScheme = colorScheme
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Update color scheme
        context.coordinator.colorScheme = colorScheme
        
        // Only update if text actually changed (avoid infinite loop)
        let currentText = textView.string
        if currentText != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)
            context.coordinator.applySyntaxHighlighting(to: textView)
        } else {
            // Re-apply highlighting if color scheme changed
            context.coordinator.applySyntaxHighlighting(to: textView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SyntaxHighlightedEditor
        weak var textView: NSTextView?
        var colorScheme: ColorScheme = .light
        
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
            
            // Update parent binding
            parent.text = textView.string
            
            // Apply syntax highlighting asynchronously
            DispatchQueue.main.async { [weak self] in
                self?.applySyntaxHighlighting(to: textView)
            }
        }
        
        func applySyntaxHighlighting(to textView: NSTextView) {
            let text = textView.string
            guard !text.isEmpty else { return }
            
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
            
            // Apply the attributed string
            textView.textStorage?.setAttributedString(attributedString)
        }
    }
}

