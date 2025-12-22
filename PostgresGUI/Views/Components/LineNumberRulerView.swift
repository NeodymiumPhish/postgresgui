//
//  LineNumberRulerView.swift
//  PostgresGUI
//
//  Created by ghazi on 11/29/25.
//

import AppKit

/// A ruler view that displays line numbers for a text view
class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    // Cached line start offsets for O(log n) line number lookup
    private var lineStartOffsets: [Int] = [0]
    private var cachedTextHash: Int = 0

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView.enclosingScrollView?.documentView
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuild line offset cache - O(n) but only when text changes
    private func rebuildLineCache(for text: String) {
        let textHash = text.hashValue
        guard textHash != cachedTextHash else { return }

        cachedTextHash = textHash
        lineStartOffsets = [0]

        // Build array of line start positions
        let nsText = text as NSString
        let length = nsText.length
        for i in 0..<length {
            if nsText.character(at: i) == 0x0A {
                lineStartOffsets.append(i + 1)
            }
        }
    }

    /// Binary search to find line number at character offset - O(log m) where m = line count
    private func lineNumber(at characterOffset: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= characterOffset {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low + 1  // 1-indexed line numbers
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
            drawEmptyTextLineNumbers(layoutManager: layoutManager, textView: textView, attributes: textAttributes)
            return
        }

        // Calculate and draw line numbers for non-empty text
        drawLineNumbers(
            text: text,
            layoutManager: layoutManager,
            textContainer: textContainer,
            textView: textView,
            visibleRect: visibleRect,
            attributes: textAttributes
        )
    }

    // MARK: - Private Helpers

    private func drawEmptyTextLineNumbers(
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let lineHeight = layoutManager.defaultLineHeight(for: font)

        // Draw line 1
        let lineNumberString1 = "1" as NSString
        let stringSize1 = lineNumberString1.size(withAttributes: attributes)
        let drawPoint1 = NSPoint(
            x: bounds.width - stringSize1.width - 8,
            y: textView.textContainerInset.height
        )
        lineNumberString1.draw(at: drawPoint1, withAttributes: attributes)

        // Draw line 2 (next line)
        let lineNumberString2 = "2" as NSString
        let stringSize2 = lineNumberString2.size(withAttributes: attributes)
        let drawPoint2 = NSPoint(
            x: bounds.width - stringSize2.width - 8,
            y: textView.textContainerInset.height + lineHeight
        )
        lineNumberString2.draw(at: drawPoint2, withAttributes: attributes)
    }

    private func drawLineNumbers(
        text: String,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textView: NSTextView,
        visibleRect: CGRect,
        attributes: [NSAttributedString.Key: Any]
    ) {
        // Rebuild line cache if text changed - O(n) but only when needed
        rebuildLineCache(for: text)

        // Calculate visible character range
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Use binary search to find starting line number - O(log m) instead of O(n)
        var lineNumber = lineNumber(at: characterRange.location)

        // Find the line start index for the first visible line
        let lineIndex = lineNumber - 1
        var currentIndex = lineIndex < lineStartOffsets.count ? lineStartOffsets[lineIndex] : characterRange.location

        var lastYPosition: CGFloat = 0
        var lastLineHeight: CGFloat = 0
        var lastLineNumber = lineNumber

        let textLength = text.count
        let maxCharRange = NSMaxRange(characterRange)

        while currentIndex <= textLength {
            // Handle the case where we're at the end of text
            let charLength = (currentIndex < textLength) ? 1 : 0

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
            let stringSize = lineNumberString.size(withAttributes: attributes)

            let drawPoint = NSPoint(
                x: bounds.width - stringSize.width - 8,
                y: yPosition
            )
            lineNumberString.draw(at: drawPoint, withAttributes: attributes)

            // Store the last line number we drew
            lastLineNumber = lineNumber

            // Move to next line using cached offsets - O(1) lookup
            lineNumber += 1
            let nextLineIndex = lineNumber - 1
            if nextLineIndex < lineStartOffsets.count {
                currentIndex = lineStartOffsets[nextLineIndex]
            } else {
                break
            }

            // Check if we've gone beyond the visible range
            if currentIndex > maxCharRange {
                break
            }
        }

        // Draw the next line number after the last line
        if lastLineHeight > 0 {
            let nextYPosition = lastYPosition + lastLineHeight
            let nextLineNumberString = "\(lastLineNumber + 1)" as NSString
            let stringSize = nextLineNumberString.size(withAttributes: attributes)
            let drawPoint = NSPoint(
                x: bounds.width - stringSize.width - 8,
                y: nextYPosition
            )
            nextLineNumberString.draw(at: drawPoint, withAttributes: attributes)
        }
    }
}
