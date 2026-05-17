import CoreGraphics

/// CGRect 与 Maestri [[x,y],[w,h]] 格式的互转
extension CGRect {
    /// 从 Maestri JSON 格式 [[x, y], [width, height]] 转换
    init?(frameArray: [[Double]]) {
        guard frameArray.count == 2,
              frameArray[0].count == 2,
              frameArray[1].count == 2 else {
            return nil
        }
        self.init(
            x: frameArray[0][0],
            y: frameArray[0][1],
            width: frameArray[1][0],
            height: frameArray[1][1]
        )
    }

    /// 转换为 Maestri JSON 格式 [[x, y], [width, height]]
    var frameArray: [[Double]] {
        [[origin.x, origin.y], [size.width, size.height]]
    }
}
