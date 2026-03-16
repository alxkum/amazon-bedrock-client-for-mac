/*
 *  Theme.swift
 *  Vendored from HighlighterSwift (MIT License)
 *  Copyright 2026, Tony Smith
 *  Copyright 2016, Juan-Pablo Illanes
 *
 *  Bug Fix: CSS compound selector parsing (e.g. .hljs-variable.language_)
 */

#if os(OSX)
import AppKit
#elseif os(iOS)
import UIKit
#endif


private typealias HRThemeDict       = [String: [AnyHashable: AnyObject]]
private typealias HRThemeStringDict = [String: [String: String]]


public class Theme {

    // MARK: - Public Properties

    public var codeFont: HRFont!
    public var boldCodeFont: HRFont!
    public var italicCodeFont: HRFont!
    public var themeBackgroundColour: HRColor!
    public var lineSpacing: CGFloat = 0.0
    public var paraSpacing: CGFloat = 0.0
    public var isDark: Bool = false
    public var fontSize: CGFloat = 18.0


    // MARK: - Private Properties

    private var themeDict : HRThemeDict!
    private var strippedTheme : HRThemeStringDict!
    internal let theme: String
    internal var lightTheme: String!


    // MARK: - Constructor

    init(withTheme: String = "default", usingFont: HRFont? = nil) {

        self.theme = withTheme

        if let font: HRFont = usingFont {
            setCodeFont(font)
        } else if let font = HRFont(name: "courier", size: 14.0) {
            setCodeFont(font)
        } else {
            setCodeFont(HRFont.systemFont(ofSize: 14.0))
        }

        self.strippedTheme = stripTheme(self.theme)
        self.lightTheme = strippedThemeToString(self.strippedTheme)
        self.themeDict = strippedThemeToTheme(self.strippedTheme)

        var backgroundColourHex: String? = self.strippedTheme[".hljs"]?["background"]
        if backgroundColourHex == nil {
            backgroundColourHex = self.strippedTheme[".hljs"]?["background-color"]
        }

        if let bgColourHex = backgroundColourHex {
            self.themeBackgroundColour = colourFromHexString(bgColourHex)
        } else {
            self.themeBackgroundColour = HRColor.white
        }
    }


    // MARK: - Getters and Setters

    public func setCodeFont(_ font: HRFont) {

        self.codeFont = font
        self.fontSize = font.pointSize

#if os(iOS) || os(tvOS) || os(visionOS)
        let boldDescriptor    = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family:font.familyName,
                                                                  UIFontDescriptor.AttributeName.face:"Bold"])
        let italicDescriptor  = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family:font.familyName,
                                                                  UIFontDescriptor.AttributeName.face:"Italic"])
        let obliqueDescriptor = UIFontDescriptor(fontAttributes: [UIFontDescriptor.AttributeName.family:font.familyName,
                                                                  UIFontDescriptor.AttributeName.face:"Oblique"])
#else
        let boldDescriptor    = NSFontDescriptor(fontAttributes: [.family:font.familyName!,
                                                                  .face:"Bold"])
        let italicDescriptor  = NSFontDescriptor(fontAttributes: [.family:font.familyName!,
                                                                  .face:"Italic"])
        let obliqueDescriptor = NSFontDescriptor(fontAttributes: [.family:font.familyName!,
                                                                  .face:"Oblique"])
#endif

        self.boldCodeFont   = HRFont(descriptor: boldDescriptor, size: font.pointSize)
        self.italicCodeFont = HRFont(descriptor: italicDescriptor, size: font.pointSize)

        if (self.italicCodeFont == nil || self.italicCodeFont.familyName != font.familyName) {
            self.italicCodeFont = HRFont(descriptor: obliqueDescriptor, size: font.pointSize)
        }

        if (self.italicCodeFont == nil) {
            self.italicCodeFont = font
        }

        if (self.boldCodeFont == nil) {
            self.boldCodeFont = font
        }

        if (self.themeDict != nil) {
            self.themeDict = strippedThemeToTheme(self.strippedTheme)
        }
    }


    // MARK: - Private Functions

    internal func applyStyleToString(_ string: String, styleList: [String]) -> NSAttributedString {

        let returnString: NSAttributedString

        let spacedParaStyle: NSMutableParagraphStyle = NSMutableParagraphStyle.init()
        spacedParaStyle.lineSpacing = (self.lineSpacing >= 0.0 ? self.lineSpacing : 0.0)
        spacedParaStyle.paragraphSpacing = (self.paraSpacing >= 0.0 ? self.paraSpacing : 0.0)

        if styleList.count > 0 {
            var attrs = [AttributedStringKey: Any]()
            attrs[.font] = self.codeFont
            attrs[.paragraphStyle] = spacedParaStyle
            for style in styleList {
                if let themeStyle = self.themeDict[style] as? [AttributedStringKey: Any] {
                    for (attrName, attrValue) in themeStyle {
                        attrs.updateValue(attrValue, forKey: attrName)
                    }
                }
            }

            returnString = NSAttributedString(string: string, attributes:attrs)
        } else {
            returnString = NSAttributedString(string: string,
                                              attributes:[.font: codeFont as Any,
                                                          .paragraphStyle: spacedParaStyle])
        }

        return returnString
    }


    // BUG FIX: Pre-process CSS to split compound selectors like .hljs-variable.language_
    // into comma-separated selectors that the existing regex can handle.
    private func stripTheme(_ themeString : String) -> HRThemeStringDict {

        // Convert compound selectors (.hljs-variable.language_) to comma-separated
        let preprocessed = themeString.replacingOccurrences(
            of: "([a-zA-Z0-9_])\\.",
            with: "$1,.",
            options: .regularExpression
        )
        let objcString: NSString = (preprocessed as NSString)
        let cssRegex = try! NSRegularExpression(pattern: "(?:(\\.[a-zA-Z0-9\\-_]*(?:[, ]\\.[a-zA-Z0-9\\-_]*)*)\\{([^\\}]*?)\\})",
                                                options:[.caseInsensitive])
        let results = cssRegex.matches(in: preprocessed,
                                       options: [.reportCompletion],
                                       range: NSMakeRange(0, objcString.length))
        var resultDict = [String: [String: String]]()

        for result in results {
            if result.numberOfRanges == 3 {
                var attributes = [String:String]()
                let cssPairs = objcString.substring(with: result.range(at: 2)).components(separatedBy: ";")
                for pair in cssPairs {
                    let cssPropComp = pair.components(separatedBy: ":")
                    if (cssPropComp.count == 2) {
                        attributes[cssPropComp[0]] = cssPropComp[1]
                    }
                }

                if attributes.count > 0 {
                    if resultDict[objcString.substring(with: result.range(at: 1))] != nil {
                        let existingAttributes: [String: String] = resultDict[objcString.substring(with: result.range(at: 1))]!
                        resultDict[objcString.substring(with: result.range(at: 1))] = existingAttributes.merging(attributes, uniquingKeysWith: { (first, _) in first })
                    } else {
                        resultDict[objcString.substring(with: result.range(at: 1))] = attributes
                    }
                }
            }
        }

        var returnDict = [String: [String: String]]()
        for (keys, result) in resultDict {
            let keyArray = keys.replacingOccurrences(of: " ", with: ",").components(separatedBy: ",")
            for key in keyArray {
                var props : [String: String]?
                props = returnDict[key]
                if props == nil {
                    props = [String:String]()
                }

                for (pName, pValue) in result {
                    props!.updateValue(pValue, forKey: pName)
                }

                returnDict[key] = props!
            }
        }

        return returnDict
    }


    private func strippedThemeToString(_ themeStringDict: HRThemeStringDict) -> String {

        var resultString: String = ""
        for (key, props) in themeStringDict {
            resultString += (key + "{")
            for (cssProp, val) in props {
                if key != ".hljs" || (cssProp.lowercased() != "background-color" && cssProp.lowercased() != "background") {
                    resultString += "\(cssProp):\(val);"
                }
            }

            resultString += "}"
        }

        return resultString
    }


    private func strippedThemeToTheme(_ themeStringDict: HRThemeStringDict) -> HRThemeDict {

        var returnTheme = HRThemeDict()
        for (className, props) in themeStringDict {
            var keyProps = [AttributedStringKey: AnyObject]()
            for (key, prop) in props {
                switch key {
                case "color":
                    keyProps[attributeForCSSKey(key)] = colourFromHexString(prop)
                case "font-style":
                    keyProps[attributeForCSSKey(key)] = fontForCSSStyle(prop)
                case "font-weight":
                    keyProps[attributeForCSSKey(key)] = fontForCSSStyle(prop)
                case "background-color":
                    keyProps[attributeForCSSKey(key)] = colourFromHexString(prop)
                default:
                    break
                }
            }

            if keyProps.count > 0 {
                let key: String = className.replacingOccurrences(of: ".", with: "")
                returnTheme[key] = keyProps
            }
        }

        return returnTheme
    }


    internal func fontForCSSStyle(_ fontStyle: String) -> HRFont {

        switch fontStyle {
            case "bold", "bolder", "600", "700", "800", "900":
                return self.boldCodeFont
            case "italic", "oblique":
                return self.italicCodeFont
            default:
                return self.codeFont
        }
    }


    internal func attributeForCSSKey(_ key: String) -> AttributedStringKey {

        switch key {
        case "color":
            return .foregroundColor
        case "font-weight":
            return .font
        case "font-style":
            return .font
        case "background-color":
            return .backgroundColor
        default:
            return .font
        }
    }


    internal func colourFromHexString(_ colourValue: String) -> HRColor {

        var colourString: String = colourValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if (colourString.hasPrefix("#")) {
            colourString = (colourString as NSString).substring(from: 1)
        } else {
            switch colourString {
            case "white":
                return HRColor.init(white: 1.0, alpha: 1.0)
            case "black":
                return HRColor.init(white: 0.0, alpha: 1.0)
            case "red":
                return HRColor.init(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
            case "green":
                return HRColor.init(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
            case "blue":
                return HRColor.init(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
            case "navy":
                return HRColor.init(red: 0.0, green: 0.0, blue: 0.5, alpha: 1.0)
            case "silver":
                return HRColor.init(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0)
            default:
                return HRColor.gray
            }
        }

        if colourString.count != 8 && colourString.count != 6 && colourString.count != 3 {
            return HRColor.gray
        }

        var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, a: UInt64 = 0
        var divisor: CGFloat
        var alpha: CGFloat = 1.0

        if colourString.count == 6 || colourString.count == 8 {
            let rString: String = (colourString as NSString).substring(to: 2)
            let gString: String = ((colourString as NSString).substring(from: 2) as NSString).substring(to: 2)
            let bString: String = ((colourString as NSString).substring(from: 4) as NSString).substring(to: 2)

            Scanner(string: rString).scanHexInt64(&r)
            Scanner(string: gString).scanHexInt64(&g)
            Scanner(string: bString).scanHexInt64(&b)

            divisor = 255.0

            if colourString.count == 8 {
                let aString: String = ((colourString as NSString).substring(from: 6) as NSString).substring(to: 2)
                Scanner(string: aString).scanHexInt64(&a)
                alpha = CGFloat(a) / divisor
            }
        } else {
            let rString: String = (colourString as NSString).substring(to: 1)
            let gString: String = ((colourString as NSString).substring(from: 1) as NSString).substring(to: 1)
            let bString: String = ((colourString as NSString).substring(from: 2) as NSString).substring(to: 1)

            Scanner(string: rString).scanHexInt64(&r)
            Scanner(string: gString).scanHexInt64(&g)
            Scanner(string: bString).scanHexInt64(&b)

            divisor = 15.0
        }

        return HRColor(red: CGFloat(r) / divisor, green: CGFloat(g) / divisor, blue: CGFloat(b) / divisor, alpha: alpha)
    }
}
