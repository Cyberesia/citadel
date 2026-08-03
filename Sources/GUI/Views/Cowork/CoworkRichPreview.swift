import SwiftUI
import WebKit

struct CoworkHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: nil)
    }
}

import PDFKit

struct CoworkPDFPreview: View {
    let data: Data

    var body: some View {
        if let doc = PDFDocument(data: data) {
            PDFKitView(document: doc)
        } else {
            Text(L10n.pdfLoadFailed)
                .font(.ps(11))
                .foregroundStyle(PrismTheme.textSecondary)
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

struct CoworkDiffPreview: View {
    let oldText: String
    let newText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(diffLines().enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.ps(10, design: .monospaced))
                        .foregroundStyle(line.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
    }

    private struct DiffLine {
        let text: String
        let color: Color
    }

    private func diffLines() -> [DiffLine] {
        let oldLines = oldText.components(separatedBy: .newlines)
        let newLines = newText.components(separatedBy: .newlines)
        let maxCount = max(oldLines.count, newLines.count)
        var result: [DiffLine] = []
        for index in 0..<maxCount {
            let old = index < oldLines.count ? oldLines[index] : nil
            let new = index < newLines.count ? newLines[index] : nil
            if old == new, let line = old {
                result.append(DiffLine(text: "  \(line)", color: PrismTheme.textSecondary))
            } else {
                if let old { result.append(DiffLine(text: "- \(old)", color: PrismTheme.signalDeny)) }
                if let new { result.append(DiffLine(text: "+ \(new)", color: .green.opacity(0.85))) }
            }
        }
        return result
    }
}
