// CGPoint, CGSize, CGVector, CGRect and CGAffineTransform helpers of the Swift 5.4 CoreGraphics overlay (lines 233-545 of CoreGraphics.swift)
import CoreGraphics
//===----------------------------------------------------------------------===//
// CGGeometry
//===----------------------------------------------------------------------===//

public extension CGPoint {
  static var zero: CGPoint {
    @_transparent // @fragile
    get { return CGPoint(x: 0, y: 0) }
  }

  @_transparent // @fragile
  init(x: Int, y: Int) {
    self.init(x: CGFloat(x), y: CGFloat(y))
  }

  @_transparent // @fragile
  init(x: Double, y: Double) {
    self.init(x: CGFloat(x), y: CGFloat(y))
  }
  
}

extension CGPoint : CustomReflectable {
  public var customMirror: Mirror {
    return Mirror(self, children: ["x": x, "y": y], displayStyle: .`struct`)
  }
}

extension CGPoint : _CustomPlaygroundQuickLookable {
  @available(*, deprecated, message: "CGPoint.customPlaygroundQuickLook will be removed in a future Swift version")
  public var customPlaygroundQuickLook: PlaygroundQuickLook {
    return .point(Double(x), Double(y))
  }
}

extension CGPoint : CustomDebugStringConvertible {
  public var debugDescription: String {
    return "(\(x), \(y))"
  }
}

extension CGPoint : Equatable {
  @_transparent // @fragile
  public static func == (lhs: CGPoint, rhs: CGPoint) -> Bool {
    return lhs.x == rhs.x  &&  lhs.y == rhs.y
  }
}

extension CGPoint : Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let x = try container.decode(CGFloat.self)
    let y = try container.decode(CGFloat.self)
    self.init(x: x, y: y)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(x)
    try container.encode(y)
  }
}

public extension CGSize {
  static var zero: CGSize {
    @_transparent // @fragile
    get { return CGSize(width: 0, height: 0) }
  }

  @_transparent // @fragile
  init(width: Int, height: Int) {
    self.init(width: CGFloat(width), height: CGFloat(height))
  }

  @_transparent // @fragile
  init(width: Double, height: Double) {
    self.init(width: CGFloat(width), height: CGFloat(height))
  }

}

extension CGSize : CustomReflectable {
  public var customMirror: Mirror {
    return Mirror(
      self,
      children: ["width": width, "height": height],
      displayStyle: .`struct`)
  }
}

extension CGSize : _CustomPlaygroundQuickLookable {
  @available(*, deprecated, message: "CGSize.customPlaygroundQuickLook will be removed in a future Swift version")
  public var customPlaygroundQuickLook: PlaygroundQuickLook {
    return .size(Double(width), Double(height))
  }
}

extension CGSize : CustomDebugStringConvertible {
  public var debugDescription : String {
    return "(\(width), \(height))"
  }
}

extension CGSize : Equatable {
  @_transparent // @fragile
  public static func == (lhs: CGSize, rhs: CGSize) -> Bool {
    return lhs.width == rhs.width  &&  lhs.height == rhs.height
  }
}

extension CGSize : Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let width = try container.decode(CGFloat.self)
    let height = try container.decode(CGFloat.self)
    self.init(width: width, height: height)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(width)
    try container.encode(height)
  }
}

public extension CGVector {
  static var zero: CGVector {
    @_transparent // @fragile
    get { return CGVector(dx: 0, dy: 0) }
  }

  @_transparent // @fragile
  init(dx: Int, dy: Int) {
    self.init(dx: CGFloat(dx), dy: CGFloat(dy))
  }

  @_transparent // @fragile
  init(dx: Double, dy: Double) {
    self.init(dx: CGFloat(dx), dy: CGFloat(dy))
  }
}

extension CGVector : Equatable {
  @_transparent // @fragile
  public static func == (lhs: CGVector, rhs: CGVector) -> Bool {
    return lhs.dx == rhs.dx  &&  lhs.dy == rhs.dy
  }
}

extension CGVector : CustomDebugStringConvertible {
  public var debugDescription : String {
    return "(\(dx), \(dy))"
  }
}

extension CGVector : Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let dx = try container.decode(CGFloat.self)
    let dy = try container.decode(CGFloat.self)
    self.init(dx: dx, dy: dy)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(dx)
    try container.encode(dy)
  }
}

public extension CGRect {
  static var zero: CGRect {
    @_transparent // @fragile
    get { return CGRect(x: 0, y: 0, width: 0, height: 0) }
  }

  @_transparent // @fragile
  init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    self.init(origin: CGPoint(x: x, y: y),
              size: CGSize(width: width, height: height))
  }

  @_transparent // @fragile
  init(x: Double, y: Double, width: Double, height: Double) {
    self.init(origin: CGPoint(x: x, y: y),
              size: CGSize(width: width, height: height))
  }

  @_transparent // @fragile
  init(x: Int, y: Int, width: Int, height: Int) {
    self.init(origin: CGPoint(x: x, y: y),
              size: CGSize(width: width, height: height))
  }


  @_transparent // @fragile
  func divided(atDistance: CGFloat, from fromEdge: CGRectEdge)
    -> (slice: CGRect, remainder: CGRect)
  {
    var slice = CGRect.zero
    var remainder = CGRect.zero
    self.__divided(slice: &slice, remainder: &remainder, atDistance: atDistance,
           from: fromEdge)
    return (slice, remainder)
  }

  @available(*, unavailable, renamed: "minX")
  var x: CGFloat { return minX }

  @available(*, unavailable, renamed: "minY")
  var y: CGFloat { return minY }
}

extension CGRect : CustomReflectable {
  public var customMirror: Mirror {
    return Mirror(
      self,
      children: ["origin": origin, "size": size],
      displayStyle: .`struct`)
  }
}

extension CGRect : _CustomPlaygroundQuickLookable {
  @available(*, deprecated, message: "CGRect.customPlaygroundQuickLook will be removed in a future Swift version")
  public var customPlaygroundQuickLook: PlaygroundQuickLook {
    return .rectangle(
      Double(origin.x), Double(origin.y),
      Double(size.width), Double(size.height))
  }
}

extension CGRect : CustomDebugStringConvertible {
  public var debugDescription : String {
    return "(\(origin.x), \(origin.y), \(size.width), \(size.height))"
  }
}

extension CGRect : Equatable {
  @_transparent // @fragile
  public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
    return lhs.equalTo(rhs)
  }
}

extension CGRect : Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let origin = try container.decode(CGPoint.self)
    let size = try container.decode(CGSize.self)
    self.init(origin: origin, size: size)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(origin)
    try container.encode(size)
  }
}

extension CGAffineTransform {
  public static var identity: CGAffineTransform {
   @_transparent // @fragile
   get { return CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
 }
}

extension CGAffineTransform : Codable {
  public init(from decoder: Decoder) throws {
    var container = try decoder.unkeyedContainer()
    let a = try container.decode(CGFloat.self)
    let b = try container.decode(CGFloat.self)
    let c = try container.decode(CGFloat.self)
    let d = try container.decode(CGFloat.self)
    let tx = try container.decode(CGFloat.self)
    let ty = try container.decode(CGFloat.self)
    self.init(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()
    try container.encode(a)
    try container.encode(b)
    try container.encode(c)
    try container.encode(d)
    try container.encode(tx)
    try container.encode(ty)
  }
}

