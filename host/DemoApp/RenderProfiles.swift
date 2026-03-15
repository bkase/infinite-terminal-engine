import AppKit
import CoreText
import Foundation

struct RenderProfileManifest: Decodable {
    let profiles: [RenderProfile]
}

struct RenderProfile: Decodable, Identifiable {
    let id: String
    let themeID: String
    let pointSize: CGFloat
    let cellWidth: CGFloat
    let lineHeight: CGFloat
    let paddingX: CGFloat
    let paddingY: CGFloat
    let titlebarHeight: CGFloat
    let regularFontFile: String
    let boldFontFile: String
    let italicFontFile: String

    func surfaceLogicalSize(cols: Int, rows: Int) -> CGSize {
        let logicalWidth = CGFloat(cols) * cellWidth + (paddingX * 2)
        let logicalHeight = CGFloat(rows) * lineHeight + (paddingY * 2) + titlebarHeight
        return CGSize(width: logicalWidth, height: logicalHeight)
    }

    func surfacePixelSize(cols: Int, rows: Int, backingScale: CGFloat) -> CGSize {
        TextureBudgetPolicy.pixelSize(cols: cols, rows: rows, profile: self, backingScale: backingScale)
    }

    func validate(in bundle: Bundle) throws {
        _ = try loadFont(named: regularFontFile, in: bundle)
        _ = try loadFont(named: boldFontFile, in: bundle)
        _ = try loadFont(named: italicFontFile, in: bundle)

        let regularFont = try loadFont(named: regularFontFile, in: bundle)
        let metrics = measure(font: regularFont)
        if metrics.cellWidth != cellWidth || metrics.lineHeight != lineHeight {
            throw RenderProfileError.metricDrift(
                profileID: id,
                expectedCellWidth: cellWidth,
                actualCellWidth: metrics.cellWidth,
                expectedLineHeight: lineHeight,
                actualLineHeight: metrics.lineHeight
            )
        }
    }

    private func loadFont(named resourceName: String, in bundle: Bundle) throws -> CTFont {
        let resourceURL = try fontURL(named: resourceName, in: bundle)
        var registerError: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(resourceURL as CFURL, .process, &registerError)

        guard
            let provider = CGDataProvider(url: resourceURL as CFURL),
            let cgFont = CGFont(provider),
            let postScriptName = cgFont.postScriptName
        else {
            throw RenderProfileError.invalidFontFile(resourceName)
        }

        return CTFontCreateWithName(postScriptName, pointSize, nil)
    }

    private func fontURL(named resourceName: String, in bundle: Bundle) throws -> URL {
        let nsName = resourceName as NSString
        let basename = nsName.deletingPathExtension
        let ext = nsName.pathExtension
        guard let url = bundle.url(forResource: basename, withExtension: ext, subdirectory: "Fonts") else {
            throw RenderProfileError.missingFontAsset(resourceName)
        }
        return url
    }

    private func measure(font: CTFont) -> (cellWidth: CGFloat, lineHeight: CGFloat) {
        var glyph = CGGlyph()
        var character = UniChar(77)
        let didMap = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        let advance = didMap ? CTFontGetAdvancesForGlyphs(font, .horizontal, [glyph], nil, 1) : 0
        let lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        return (cellWidth: ceil(advance), lineHeight: lineHeight)
    }
}

enum RenderProfileError: LocalizedError {
    case missingManifest
    case emptyManifest
    case missingProfile(String)
    case missingFontAsset(String)
    case invalidFontFile(String)
    case metricDrift(profileID: String, expectedCellWidth: CGFloat, actualCellWidth: CGFloat, expectedLineHeight: CGFloat, actualLineHeight: CGFloat)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Missing RenderProfiles.json resource."
        case .emptyManifest:
            return "RenderProfiles.json does not contain any profiles."
        case .missingProfile(let id):
            return "Missing render profile '\(id)'."
        case .missingFontAsset(let filename):
            return "Missing collaborative font asset '\(filename)'."
        case .invalidFontFile(let filename):
            return "Unable to load collaborative font '\(filename)'."
        case let .metricDrift(profileID, expectedCellWidth, actualCellWidth, expectedLineHeight, actualLineHeight):
            return "Render profile '\(profileID)' drifted: expected \(expectedCellWidth)x\(expectedLineHeight), got \(actualCellWidth)x\(actualLineHeight)."
        }
    }
}

enum RenderProfileCatalog {
    static let defaultProfileID = "collab-pragmata-v1"

    static func load(in bundle: Bundle = .module) throws -> [RenderProfile] {
        guard let manifestURL = bundle.url(forResource: "RenderProfiles", withExtension: "json") else {
            throw RenderProfileError.missingManifest
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(RenderProfileManifest.self, from: data)
        guard !manifest.profiles.isEmpty else {
            throw RenderProfileError.emptyManifest
        }
        try manifest.profiles.forEach { try $0.validate(in: bundle) }
        return manifest.profiles
    }

    static func defaultProfile(in bundle: Bundle = .module) throws -> RenderProfile {
        let profiles = try load(in: bundle)
        guard let profile = profiles.first(where: { $0.id == defaultProfileID }) else {
            throw RenderProfileError.missingProfile(defaultProfileID)
        }
        return profile
    }
}
