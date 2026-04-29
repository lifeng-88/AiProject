#!/usr/bin/env swift
import Foundation

/// 将 String Catalog 中 `zh-Hans` 文案转为繁体并改名为 `zh-Hant`（CFStringTransform Hans-Hant）
let inputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/bbb/Localizable.xcstrings"

func hansToHant(_ s: String) -> String {
    let m = NSMutableString(string: s)
    CFStringTransform(m, nil, "Hans-Hant" as CFString, false)
    return String(m)
}

func convertZhHansBranch(_ obj: Any) -> Any {
    if let dict = obj as? [String: Any] {
        var result: [String: Any] = [:]
        for (k, v) in dict {
            if k == "value", let s = v as? String {
                result[k] = hansToHant(s)
            } else {
                result[k] = convertZhHansBranch(v)
            }
        }
        return result
    }
    if let arr = obj as? [Any] {
        return arr.map { convertZhHansBranch($0) }
    }
    return obj
}

func processNode(_ obj: Any) -> Any {
    guard var dict = obj as? [String: Any] else {
        if let arr = obj as? [Any] { return arr.map { processNode($0) } }
        return obj
    }
    if var locs = dict["localizations"] as? [String: Any], locs["zh-Hans"] != nil {
        let converted = convertZhHansBranch(locs["zh-Hans"]!)
        locs["zh-Hant"] = converted
        locs.removeValue(forKey: "zh-Hans")
        dict["localizations"] = locs
    }
    for (k, v) in dict {
        dict[k] = processNode(v)
    }
    return dict
}

let url = URL(fileURLWithPath: inputPath)
guard let data = try? Data(contentsOf: url) else {
    fputs("Cannot read: \(inputPath)\n", stderr)
    exit(1)
}
guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fputs("Invalid JSON root\n", stderr)
    exit(1)
}
if let strings = root["strings"] {
    root["strings"] = processNode(strings)
}
let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
try out.write(to: url, options: .atomic)
print("OK: \(inputPath)")
