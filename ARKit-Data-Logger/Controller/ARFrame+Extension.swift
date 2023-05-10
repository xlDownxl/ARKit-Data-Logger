//
//  ARFrame+Extension.swift
//  DepthMap
//
//  Created by MacBook Pro M1 on 2021/04/20.
//

import ARKit

extension URL {
    var typeIdentifier: String? { (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier }
    var isMP3: Bool { typeIdentifier == "public.mp3" }
    var localizedName: String? { (try? resourceValues(forKeys: [.localizedNameKey]))?.localizedName }
    var hasHiddenExtension: Bool {
        get { (try? resourceValues(forKeys: [.hasHiddenExtensionKey]))?.hasHiddenExtension == true }
        set {
            var resourceValues = URLResourceValues()
            resourceValues.hasHiddenExtension = newValue
            try? setResourceValues(resourceValues)
        }
    }
}

// MARK: - ARFrame extension
extension ARFrame {
    var depthMap: CVPixelBuffer? {
        guard let depthMap =  self.sceneDepth?.depthMap else { //self.smoothedSceneDepth?.depthMap ??
            return nil
        }
        
        return depthMap
    }
    
    var depthMapImage: UIImage? {
        guard let depthMap = self.depthMap else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: depthMap)
        let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
        guard let image = cgImage else { return nil }
        return UIImage(cgImage: image)
    }
    
    var capturedImageAsDepthMapScale: UIImage? {
        let capturedImage = self.capturedImage
        
        let imageWidth = CVPixelBufferGetWidth(capturedImage)
        let imageHeight = CVPixelBufferGetHeight(capturedImage)
        print(imageWidth)
        print(imageHeight)
        
        let scaleX = 640.0 / Double(imageWidth)  //256
        let scaleY = 480.0 / Double(imageHeight)  //192
        print(scaleX)
        print(scaleY)
        
        let ciImage = CIImage(cvPixelBuffer: capturedImage)
        // resize as the scale of depth map
        let resizedImage = ciImage.resize(scaleX: scaleX, scaleY: scaleY)
        
        guard let resizedImage = resizedImage else {
            return nil
        }

        let cgImage = CIContext().createCGImage(resizedImage, from: resizedImage.extent)
        guard let image = cgImage else { return nil }
        return UIImage(cgImage: image)
    }
}

// MARK: - CIImage extension
extension CIImage {
    /// https://qiita.com/yyokii/items/8d462ba0df69fcfe29d2
    func resize(scaleX: CGFloat, scaleY: CGFloat) -> CIImage? {
        let matrix = CGAffineTransform(scaleX: scaleX, y: scaleY)
        return self.transformed(by: matrix)
    }
}
