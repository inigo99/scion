// LocalizedStringResource and String(localized:) (Foundation, macOS 13) for scion's Foundation overlay: a key looked
// up in a bundle's Localizable tables. ponytail: no String.LocalizationValue, defaultValue or explicit locale yet.
public struct LocalizedStringResource: Equatable, Hashable, ExpressibleByStringInterpolation, CustomStringConvertible, @unchecked Sendable {
    public var key: String
    public var table: String?
    public var locale: Locale
    var bundle: Bundle
    public init(_ key: String, table: String? = nil, locale: Locale = .current, bundle: Bundle = .main) {
        self.key = key; self.table = table; self.locale = locale; self.bundle = bundle
    }
    public init(stringLiteral value: String) { self.init(value) }
    public init(stringInterpolation: DefaultStringInterpolation) { self.init(String(stringInterpolation: stringInterpolation)) }
    public var description: String { String(localized: self) }
}
extension String {
    public init(localized resource: LocalizedStringResource) {
        self = resource.bundle.localizedString(forKey: resource.key, value: nil, table: resource.table)
    }
}
