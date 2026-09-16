import Foundation

// MARK: - xlsx writer
//
// One file, five tabs. A CSV holds exactly one table, so four related tables
// meant four downloads and no way to say how they join.
//
// An .xlsx is a ZIP of XML, and ZIP permits store-only, so the whole format
// reduces to string building plus a CRC32. That is why there is no dependency
// here: adding a Swift spreadsheet package to ship one export is a worse trade
// than 150 lines that do exactly what we need and nothing else.
enum XLSXWriter {

    struct Sheet {
        let name: String
        /// Row 0 is the header row and is styled bold-on-grey.
        let rows: [[Cell]]
        var freezeHeader: Bool = true
        var columnWidth: Double = 14
    }

    enum Cell {
        case text(String)
        case number(Double)
        case int(Int)
        case bool(Bool)
        case empty

        static func opt(_ v: Double?) -> Cell { v.map { .number($0) } ?? .empty }
        static func opt(_ v: Int?) -> Cell { v.map { .int($0) } ?? .empty }
        static func opt(_ v: String?) -> Cell {
            guard let v, !v.isEmpty else { return .empty }
            return .text(v)
        }
    }

    // MARK: Public

    static func write(_ sheets: [Sheet], to url: URL) throws {
        var files: [(String, String)] = [
            ("[Content_Types].xml", contentTypes(sheets.count)),
            ("_rels/.rels", rootRels),
            ("xl/workbook.xml", workbook(sheets)),
            ("xl/_rels/workbook.xml.rels", workbookRels(sheets.count)),
            ("xl/styles.xml", styles),
        ]
        for (i, s) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml", sheetXML(s)))
        }
        try zip(files).write(to: url, options: .atomic)
    }

    // MARK: XML

    /// Excel refuses to open a file containing a raw control character in an
    /// inline string, and voice-memo text is the field most likely to carry one.
    private static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + 8)
        for ch in s.unicodeScalars {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&apos;"
            case "\n", "\t": out.unicodeScalars.append(ch)
            default:
                if ch.value >= 0x20 || ch.value == 0x0A || ch.value == 0x09 {
                    out.unicodeScalars.append(ch)
                }   // anything else is dropped
            }
        }
        return out
    }

    private static func colName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(65 + r)!) + name
            n = (n - r - 1) / 26
        }
        return name
    }

    private static func sheetXML(_ s: Sheet) -> String {
        let widest = s.rows.map(\.count).max() ?? 1
        let cols = "<cols><col min=\"1\" max=\"\(widest)\" width=\"\(s.columnWidth)\" customWidth=\"1\"/></cols>"
        let view = s.freezeHeader
            ? "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
            : "<sheetViews><sheetView workbookViewId=\"0\" showGridLines=\"0\"/></sheetViews>"

        var body = ""
        for (ri, row) in s.rows.enumerated() {
            var cells = ""
            for (ci, cell) in row.enumerated() {
                let ref = "\(colName(ci))\(ri + 1)"
                let style = (ri == 0 && s.freezeHeader) ? " s=\"1\"" : ""
                switch cell {
                case .empty: continue
                case .number(let v):
                    guard v.isFinite else { continue }
                    cells += "<c r=\"\(ref)\"\(style)><v>\(v)</v></c>"
                case .int(let v):
                    cells += "<c r=\"\(ref)\"\(style)><v>\(v)</v></c>"
                case .bool(let v):
                    cells += "<c r=\"\(ref)\"\(style) t=\"b\"><v>\(v ? 1 : 0)</v></c>"
                case .text(let v):
                    cells += "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(v))</t></is></c>"
                }
            }
            body += "<row r=\"\(ri + 1)\">\(cells)</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\(view)\(cols)<sheetData>\(body)</sheetData></worksheet>
        """
    }

    private static func contentTypes(_ n: Int) -> String {
        let overrides = (1...n).map {
            "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(overrides)</Types>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func workbook(_ sheets: [Sheet]) -> String {
        let tags = sheets.enumerated().map {
            "<sheet name=\"\(esc($1.name))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(tags)</sheets></workbook>
        """
    }

    private static func workbookRels(_ n: Int) -> String {
        let rels = (1...n).map {
            "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)<Relationship Id="rId\(n + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """
    }

    /// Two fonts, two cellXfs: plain Arial 10, and bold on paper-deep for headers.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8E4DF"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs></styleSheet>
    """

    // MARK: ZIP (store only)

    private static func crc32(_ data: [UInt8]) -> UInt32 {
        struct T { static let table: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        } }
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = T.table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    private static func zip(_ files: [(String, String)]) -> Data {
        var body: [UInt8] = [], central: [UInt8] = []
        var offset: UInt32 = 0

        for (name, contents) in files {
            let nameBytes = Array(name.utf8)
            let data = Array(contents.utf8)
            let crc = crc32(data)
            let size = UInt32(data.count)

            var local: [UInt8] = le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0)
            local += le16(0) + le16(0)                       // mod time / date
            local += le32(crc) + le32(size) + le32(size)
            local += le16(UInt16(nameBytes.count)) + le16(0)
            body += local + nameBytes + data

            var cd: [UInt8] = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0)
            cd += le16(0) + le16(0)
            cd += le32(crc) + le32(size) + le32(size)
            cd += le16(UInt16(nameBytes.count)) + le16(0) + le16(0)
            cd += le16(0) + le16(0) + le32(0) + le32(offset)
            central += cd + nameBytes

            offset += UInt32(local.count + nameBytes.count + data.count)
        }

        let eocd = le32(0x0605_4B50) + le16(0) + le16(0)
            + le16(UInt16(files.count)) + le16(UInt16(files.count))
            + le32(UInt32(central.count)) + le32(offset) + le16(0)
        return Data(body + central + eocd)
    }
}
