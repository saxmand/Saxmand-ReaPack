import Foundation
import Vision
import CoreImage

guard CommandLine.arguments.count > 1 else {
    print("{\"error\":\"no path\"}"); exit(1)
}
let path = CommandLine.arguments[1]
let url  = URL(fileURLWithPath: path)
guard let ci = CIImage(contentsOf: url) else {
    print("{\"error\":\"cannot load image\"}"); exit(1)
}
let req = VNClassifyImageRequest()
let handler = VNImageRequestHandler(ciImage: ci, options: [:])
try? handler.perform([req])

// Vision spreads confidence across many labels; 0.01 keeps the meaningful ones
let skip: Set<String> = ["abstract","clipart","vector","illustration"]
var pairs: [(Float,String)] = []
for obs in (req.results ?? []) {
    guard obs.confidence > 0.01 else { continue }
    // Identifiers use underscores: "animal_pet_dog" → "animal pet dog"
    let label = obs.identifier.replacingOccurrences(of:"_", with:" ")
    if !skip.contains(label) { pairs.append((obs.confidence, label)) }
}
pairs.sort { $0.0 > $1.0 }
let top = pairs.prefix(3).map { $0.1 }
let inner = top.map { "\"" + $0.replacingOccurrences(of:"\"",with:"\\\"") + "\"" }.joined(separator:",")
print("{\"labels\":[\(inner)]}")
