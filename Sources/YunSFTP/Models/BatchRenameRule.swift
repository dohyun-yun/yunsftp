import Foundation

public enum RenameActionType: String, CaseIterable, Identifiable {
    case replaceText = "Replace Text"
    case addPrefix = "Add Prefix"
    case addSuffix = "Add Suffix"
    case changeCase = "Change Case"
    case numbering = "Numbering"

    public var id: String { rawValue }
}

public enum CaseType: String, CaseIterable, Identifiable {
    case lowercase = "lowercase"
    case uppercase = "UPPERCASE"
    case capitalized = "Capitalized Case"

    public var id: String { rawValue }
}

public struct BatchRenameRule {
    public var actionType: RenameActionType = .replaceText
    public var findText: String = ""
    public var replaceText: String = ""
    public var caseSensitive: Bool = false
    public var prefixText: String = ""
    public var suffixText: String = ""
    public var caseType: CaseType = .lowercase
    public var startNumber: Int = 1
    public var stepNumber: Int = 1
    public var paddingDigits: Int = 2
    public var applyToExtension: Bool = false

    public init() {}

    public func apply(to originalName: String, index: Int) -> String {
        let ext = (originalName as NSString).pathExtension
        let base = (originalName as NSString).deletingPathExtension

        var targetBase = base
        var targetExt = ext

        switch actionType {
        case .replaceText:
            if !findText.isEmpty {
                let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                targetBase = targetBase.replacingOccurrences(of: findText, with: replaceText, options: options)
                if applyToExtension && !targetExt.isEmpty {
                    targetExt = targetExt.replacingOccurrences(of: findText, with: replaceText, options: options)
                }
            }

        case .addPrefix:
            targetBase = prefixText + targetBase

        case .addSuffix:
            targetBase = targetBase + suffixText

        case .changeCase:
            switch caseType {
            case .lowercase:
                targetBase = targetBase.lowercased()
                if applyToExtension { targetExt = targetExt.lowercased() }
            case .uppercase:
                targetBase = targetBase.uppercased()
                if applyToExtension { targetExt = targetExt.uppercased() }
            case .capitalized:
                targetBase = targetBase.capitalized
                if applyToExtension { targetExt = targetExt.capitalized }
            }

        case .numbering:
            let num = startNumber + (index * stepNumber)
            let formattedNum = String(format: "%0*d", paddingDigits, num)
            targetBase = "\(targetBase)_\(formattedNum)"
        }

        if targetExt.isEmpty {
            return targetBase
        } else {
            return "\(targetBase).\(targetExt)"
        }
    }
}
