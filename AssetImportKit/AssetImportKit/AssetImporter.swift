//
//  SCNAssetImporter.swift
//  AssetImportKit
//
//  Created by Eugene Bokhan on 2/11/18.
//  Copyright © 2018 Eugene Bokhan. All rights reserved.
//

import Foundation
import GLKit
import SceneKit
import SceneKit.ModelIO
import assimp.cimport

/**
 An importer that imports the files with formats supported by Assimp and
 converts the assimp scene graph into a scenekit scene graph.
 */
public struct AssetImporter {
    
    // MARK: - Bone data
    
    /**
     @name Bone data
     */
    
    /**
     The array of bone names across all meshes in all nodes.
     */
    public var boneNames: [String] = []
    
    /**
     The array of unique bone names across all meshes in all nodes.
     */
    public var uniqueBoneNames: [String] = []
    
    /**
     The array of unique bone nodes across all meshes in all nodes.
     */
    public var uniqueBoneNodes: [SCNNode] = []
    
    /**
     The dictionary of bone inverse bind transforms, where key is the bone name.
     */
    public var boneTransforms: NSMutableDictionary = NSMutableDictionary()
    
    /**
     The array of unique bone transforms for all unique bone nodes.
     */
    public var uniqueBoneTransforms: [SCNMatrix4] = []
    
    /**
     The root node of the skeleton in the scene.
     */
    public var skeleton = SCNNode()
    
    // MARK: - Loading a scene
    
    /**
     @name Loading a scene
     */
    
    /**
     Loads a scene from the specified file path.
     
     @param filePath The path to the scene file to load.
     @param postProcessFlags The flags for all possible post processing steps.
     @param error Scene import error.
     @return A new scene object, or nil if no scene could be loaded.
     */
    public mutating func importScene(filePath: String,
                                     postProcessSteps: PostProcessSteps) throws -> AssetImporterScene {
        
        // Start the import on the given file with some example postprocessing
        // Usually - if speed is not the most important aspect for you - you'll t
        // probably to request more postprocessing than we do in this example.
        guard let aiScenePointer = aiImportFile(filePath ,
                                                UInt32(postProcessSteps.rawValue)) else {
            // The pointer has a renference to nil if the import failed.
            let errorString = tupleOfInt8sToString(aiGetErrorString().pointee)
            print(" Scene importing failed for filePath \(filePath)")
            print(" Scene importing failed with error \(String(describing: errorString))")
            throw NSError(domain: "AssimpImporter", code: -1,
                          userInfo: [NSLocalizedDescriptionKey : errorString]) as Error
        }
        // Access the aiScene instance referenced by aiScenePointer.
        var aiScene = aiScenePointer.pointee
        // Now we can access the file's contents.
        let scnScene = makeSCNScene(fromAssimpScene: aiScene, atPath: filePath)
        // We're done. Release all resources associated with this import.
        aiReleaseImport(&aiScene)
        // Retutrn result
        return scnScene
    }
    
    // MARK: - Make scenekit scene
    
    /**
     @name Make scenekit scene
     */
    
    /**
     Creates a scenekit scene from the scene representing the file at a given path.
     
     @param aiScene The assimp scene.
     @param path The path to the scene file to load.
     @return A new scene object.
     */
    public mutating func makeSCNScene(fromAssimpScene aiScene: aiScene, atPath path: String) -> AssetImporterScene {
        
        print("Make an SCNScene")
        
        let aiRootNode = aiScene.mRootNode.pointee
        let assetImporterScene = AssetImporterScene()
        /*
         ---------------------------------------------------------------------
         Assign geometry, materials, lights and cameras to the node
         ---------------------------------------------------------------------
         */
        let imageCache = AssimpImageCache()
        let scnRootNode = makeSCNNode(fromAssimpNode: aiRootNode,
                                      in: aiScene,
                                      atPath: path,
                                      imageCache: imageCache)
        assetImporterScene.rootNode.addChildNode(scnRootNode)
        /*
         ---------------------------------------------------------------------
         Animations and skinning
         ---------------------------------------------------------------------
         */
        buildSkeletonDatabase(for: assetImporterScene)
        makeSkinner(forAssimpNode: aiRootNode, in: aiScene, scnScene: assetImporterScene)
        createAnimations(from: aiScene, with: assetImporterScene, atPath: path)
        /*
         ---------------------------------------------------------------------
         Make SCNScene for model and animations
         ---------------------------------------------------------------------
         */
        assetImporterScene.makeModelScene()
        assetImporterScene.makeAnimationScenes()
        
        return assetImporterScene
    }
    
    // MARK: - Make scenekit node
    
    /**
     @name Make a scenekit node
     */
    
    /**
     Creates a new scenekit node from the assimp scene node
     
     @param aiNode The assimp scene node.
     @param aiScene The assimp scene.
     @param path The path to the scene file to load.
     @return A new scene node.
     */
    public mutating func makeSCNNode(fromAssimpNode aiNode: aiNode,
                            in aiScene: aiScene,
                            atPath path: String,
                            imageCache: AssimpImageCache) -> SCNNode {
        
        let node = SCNNode()
        /*
         ---------------------------------------------------------------------
         Get the node's name
         ---------------------------------------------------------------------
         */
        let aiNodeName = aiNode.mName
        node.name = aiNodeName.stringValue()
        print("Creating node \(String(describing: node.name!)) with \(aiNode.mNumMeshes) meshes")
        /*
         ---------------------------------------------------------------------
         Make SCNGeometry
         ---------------------------------------------------------------------
         */
        let nVertices = findNumVertices(in: aiNode, in: aiScene)
        print("nVertices : \(nVertices)")
        if nVertices > 0 {
            if let nodeGeometry = makeSCNGeometry(fromAssimpNode: aiNode,
                                                  in: aiScene,
                                                  withVertices: nVertices,
                                                  atPath: path,
                                                  imageCache: imageCache) {
                node.geometry = nodeGeometry
            }
        }
        /*
         ---------------------------------------------------------------------
         Create Light
         ---------------------------------------------------------------------
         */
        node.light = node.makeSCNLight(from: aiNode, in: aiScene)
        /*
         ---------------------------------------------------------------------
         Create Camera
         ---------------------------------------------------------------------
         */
        node.camera = makeSCNCamera(fromAssimpNode: aiNode, in: aiScene)
        /*
         ---------------------------------------------------------------------
         Get bone names & bone transforms
         ---------------------------------------------------------------------
         */
        boneNames.append(contentsOf: getBoneNames(forAssimpNode: aiNode,
                                                  in: aiScene))
        boneTransforms.addEntries(from: getBoneTransforms(forAssimpNode: aiNode,
                                                          in: aiScene) as! [AnyHashable : Any])
        /*
         ---------------------------------------------------------------------
         Transform
         ---------------------------------------------------------------------
         */
        let aiNodeMatrix  = aiNode.mTransformation
        let glkNodeMatrix = GLKMatrix4Make(aiNodeMatrix.a1, aiNodeMatrix.b1, aiNodeMatrix.c1, aiNodeMatrix.d1,
                                           aiNodeMatrix.a2, aiNodeMatrix.b2, aiNodeMatrix.c2, aiNodeMatrix.d2,
                                           aiNodeMatrix.a3, aiNodeMatrix.b3, aiNodeMatrix.c3, aiNodeMatrix.d3,
                                           aiNodeMatrix.a4, aiNodeMatrix.b4, aiNodeMatrix.c4, aiNodeMatrix.d4)
        let scnMatrix = SCNMatrix4FromGLKMatrix4(glkNodeMatrix)
        node.transform = scnMatrix
        
        print("Node \(String(describing: node.name!)) position is: \(aiNodeMatrix.a4) \(aiNodeMatrix.b4) \(aiNodeMatrix.c4)")
        
        for i in 0 ..< aiNode.mNumChildren {
            
            if let aiChildNode = aiNode.mChildren[Int(i)]?.pointee {
                let childNode = makeSCNNode(fromAssimpNode: aiChildNode,
                                            in: aiScene, atPath: path,
                                            imageCache: imageCache)
                node.addChildNode(childNode)
            }
            
        }
        
        return node
    }
    
    
    // MARK: - Find the number of vertices, faces and indices of a geometry
    
    /**
     @name Find the number of vertices, faces and indices of a geometry
     */
    
    /**
     Finds the total number of vertices in the meshes of the specified node.
     
     @param aiNode The assimp scene node.
     @param aiScene The assimp scene.
     @return The number of vertices.
     */
    public func findNumVertices(in aiNode: aiNode, in aiScene: aiScene) -> Int {
        
        var nVertices: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                nVertices += Int(aiMesh.mNumVertices)
                
            }
        }
        
        return nVertices
    }
    
    /**
     Finds the total number of faces in the meshes of the specified node.
     
     @param aiNode The assimp scene node.
     @param aiScene The assimp scene.
     @return The number of faces.
     */
    public func findNumFaces(in aiNode: aiNode, in aiScene: aiScene) -> Int {
        
        var nFaces: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                nFaces += Int(aiMesh.mNumFaces)
                
            }
        }
        
        return nFaces
    }
    
    /**
     Finds the total number of indices in the specified mesh by index.
     
     @param aiMeshIndex The assimp mesh index.
     @param aiScene The assimp scene.
     @return The total number of indices.
     */
    public func findNumIndices(inMesh aiMeshIndex: Int, in aiScene: aiScene) -> Int {
        
        var nIndices: Int = 0
        if let aiMeshPointer = aiScene.mMeshes[aiMeshIndex] {
            
            let aiMesh = aiMeshPointer.pointee
            for j in 0..<aiMesh.mNumFaces {
                
                let aiFace = aiMesh.mFaces[Int(j)]
                nIndices += Int(aiFace.mNumIndices)
                
            }
        }
        
        return nIndices
    }
    
    // MARK: - Make scenekit geometry sources
    
    /**
     @name Make scenekit geometry sources
     */
    
    /**
     Creates a scenekit geometry source from the vertices of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The total number of vertices in the meshes of the aiNode.
     @return A new geometry source whose semantic property is vertex.
     */
    public func makeVertexGeometrySource(for aiNode: aiNode, in aiScene: aiScene, withNVertices nVertices: Int) -> SCNGeometrySource {
        
        let scnVertices = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        var verticesCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                if aiMesh.mVertices != nil {
                    
                    print("Getting vertices")
                    for j in 0 ..< aiMesh.mNumVertices {
                        
                        let aiVector3D = aiMesh.mVertices[Int(j)]
                        scnVertices[verticesCounter] = aiVector3D.x
                        verticesCounter += 1
                        scnVertices[verticesCounter] = aiVector3D.y
                        verticesCounter += 1
                        scnVertices[verticesCounter] = aiVector3D.z
                        verticesCounter += 1
                        
                    }
                }
            }
        }
        
        let dataLength = nVertices * 3 * MemoryLayout<Float>.size
        let data = NSData(bytes: scnVertices, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = 3 * bytesPerComponent
        let vertexSource = SCNGeometrySource(data: data, semantic: .vertex, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        scnVertices.deallocate()
        
        return vertexSource
    }
    
    /**
     Creates a scenekit geometry source from the normals of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the aiNode.
     @return A new geometry source whose semantic property is normal.
     */
    public func makeNormalGeometrySource(for aiNode: aiNode, in aiScene: aiScene, withNVertices nVertices: Int) -> SCNGeometrySource {
        
        let scnNormals = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        var verticesCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                if aiMesh.mNormals != nil {
                    
                    print("Getting normals")
                    for j in 0 ..< aiMesh.mNumVertices {
                        
                        let aiVector3D = aiMesh.mNormals[Int(j)]
                        scnNormals[verticesCounter] = aiVector3D.x
                        verticesCounter += 1
                        scnNormals[verticesCounter] = aiVector3D.y
                        verticesCounter += 1
                        scnNormals[verticesCounter] = aiVector3D.z
                        verticesCounter += 1
                        
                    }
                }
            }
        }
        
        let dataLength = nVertices * 3 * MemoryLayout<Float>.size
        let data = NSData(bytes: scnNormals, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = 3 * bytesPerComponent
        let normalSource = SCNGeometrySource(data: data, semantic: .normal, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        scnNormals.deallocate()
        
        return normalSource
    }
    
    /**
     Creates a scenekit geometry source from the tangents of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the aiNode.
     @return A new geometry source whose semantic property is tangent.
     */
    public func makeTangentGeometrySource(for aiNode: aiNode, in aiScene: aiScene, withNVertices nVertices: Int) -> SCNGeometrySource {
        
        let scnTangents = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        var verticesCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                if aiMesh.mTangents != nil {
                    
                    print("Getting tangents")
                    for j in 0 ..< aiMesh.mNumVertices {
                        
                        let aiVector3D = aiMesh.mTangents[Int(j)]
                        scnTangents[verticesCounter] = aiVector3D.x
                        verticesCounter += 1
                        scnTangents[verticesCounter] = aiVector3D.y
                        verticesCounter += 1
                        scnTangents[verticesCounter] = aiVector3D.z
                        verticesCounter += 1
                        
                    }
                }
            }
        }
        let dataLength = nVertices * 3 * MemoryLayout<Float>.size
        let data = NSData(bytes: scnTangents, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = 3 * bytesPerComponent
        let tangentSource = SCNGeometrySource(data: data, semantic: .tangent, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        scnTangents.deallocate()
        
        return tangentSource
    }
    
    /**
     Creates a scenekit geometry source from the texture coordinates of the
     makeTextureGeometrySourceForNodespecified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the node.
     @return A new geometry source whose semantic property is texcoord.
     */
    public func makeTextureGeometrySource(for aiNode: aiNode, in aiScene: aiScene, withNVertices nVertices: Int) -> SCNGeometrySource {
        
        let scnTextures = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        var verticesCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                if aiMesh.mTextureCoords.0 != nil {
                    
                    print("Getting texture coordinates")
                    for j in 0 ..< aiMesh.mNumVertices {
                        
                        let x = aiMesh.mTextureCoords.0![Int(j)].x
                        let y = aiMesh.mTextureCoords.0![Int(j)].y
                        scnTextures[verticesCounter] = x
                        verticesCounter += 1
                        scnTextures[verticesCounter] = y
                        verticesCounter += 1
                        
                    }
                }
            }
        }
        
        let dataLength = nVertices * 2 * MemoryLayout<Float>.size
        let data = NSData(bytes: scnTextures, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = 2 * bytesPerComponent
        let textureSource = SCNGeometrySource(data: data, semantic: .texcoord, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: 2, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        scnTextures.deallocate()
        
        return textureSource
    }
    
    /**
     Creates a scenekit vertex color source from the vertex color information of
     the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the node.
     @return A new color source whose semantic property is vertex color.
     */
    public func makeColorGeometrySource(for aiNode: aiNode, in aiScene: aiScene, withNVertices nVertices: Int) -> SCNGeometrySource? {
        
        let scnColors = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * 3)
        var colorsCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                let aiColor4D = aiMesh.mColors.0
                if aiColor4D == nil {
                    
                    scnColors.deallocate()
                    return nil
                    
                }
                
                for j in 0 ..< aiMesh.mNumVertices {
                    
                    scnColors[colorsCounter] = aiColor4D![Int(j)].r
                    colorsCounter += 1
                    scnColors[colorsCounter] = aiColor4D![Int(j)].g
                    colorsCounter += 1
                    scnColors[colorsCounter] = aiColor4D![Int(j)].b
                    colorsCounter += 1
                    
                }
            }
        }
        
        let dataLength = nVertices * 3 * MemoryLayout<Float>.size
        let nsData = NSData(bytes: scnColors, length: dataLength)
        let data = nsData as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = 3 * bytesPerComponent
        let colorSource = SCNGeometrySource(data: data, semantic: .color, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        scnColors.deallocate()
        
        return colorSource
    }
    
    /**
     Creates an array of geometry sources for the specifed node describing
     the vertices in the geometry and their attributes.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the node.
     @return An array of geometry sources.
     */
    public func makeGeometrySources(for aiNode: aiNode, in aiScene: aiScene, withVertices nVertices: Int) -> [SCNGeometrySource] {
        
        var scnGeometrySources: [SCNGeometrySource] = []
        scnGeometrySources.append(makeVertexGeometrySource(for: aiNode, in: aiScene, withNVertices: nVertices))
        scnGeometrySources.append(makeNormalGeometrySource(for: aiNode, in: aiScene, withNVertices: nVertices))
        scnGeometrySources.append(makeTangentGeometrySource(for: aiNode, in: aiScene, withNVertices: nVertices))
        scnGeometrySources.append(makeTextureGeometrySource(for: aiNode, in: aiScene, withNVertices: nVertices))
        if let colorGeometrySource = makeColorGeometrySource(for: aiNode, in: aiScene, withNVertices: nVertices) as SCNGeometrySource? {
            scnGeometrySources.append(colorGeometrySource)
        }
        
        return scnGeometrySources
    }
    
    // MARK: - Make scenekit geometry elements
    
    /**
     @name Make scenekit geometry elements
     */
    
    /**
     Creates a scenekit geometry element describing how vertices connect to define
     a three-dimensional object, or geometry for the specified mesh of a node.
     
     @param aiMeshIndex The assimp mesh index.
     @param aiNode The assimp node of the mesh.
     @param aiScene The assimp scene.
     @param indexOffset The total number of indices for the previous meshes.
     @param nFaces The number of faces in the geometry of the mesh.
     @return A new geometry element object.
     */
    public func makeIndicesGeometryElement(forMeshIndex aiMeshIndex: Int,
                                           in aiNode: aiNode,
                                           in aiScene: aiScene,
                                           withIndexOffset indexOffset: Int16,
                                           nFaces: Int) -> SCNGeometryElement? {
        
        var indicesCounter: Int = 0
        let nIndices = findNumIndices(inMesh: aiMeshIndex, in: aiScene)
        let scnIndices = UnsafeMutablePointer<CShort>.allocate(capacity: nIndices)
        
        if let aiMeshPointer = aiScene.mMeshes[aiMeshIndex] {
            
            let aiMesh = aiMeshPointer.pointee
            for i in 0 ..< aiMesh.mNumFaces {
                
                let aiFace = aiMesh.mFaces[Int(i)]
                // We ignore faces which are not triangulated.
                if aiFace.mNumIndices != 3 {
                    
                    return nil
                    
                }
                for j in 0 ..< aiFace.mNumIndices {
                    
                    // "Thread 1: Fatal error: Not enough bits to represent a signed value" fix.
                    let indexOffsetTempVar = NSNumber(value: indexOffset).int64Value
                    let aiFaceTempVar = NSNumber(value: aiFace.mIndices[Int(j)]).int64Value
                    let sumResult = NSNumber(value: indexOffsetTempVar + aiFaceTempVar).int16Value
                    
                    scnIndices[indicesCounter] = sumResult
                    indicesCounter += 1
                    
                }
            }
        }
        
        let dataLength = nIndices * MemoryLayout<CShort>.size
        let indicesData = NSData(bytes: scnIndices,
                                 length: dataLength) as Data
        let bytesPerIndex = MemoryLayout<CShort>.size
        let indices = SCNGeometryElement(data: indicesData,
                                         primitiveType: .triangles,
                                         primitiveCount: nFaces,
                                         bytesPerIndex: bytesPerIndex)
        
        scnIndices.deallocate()
        
        return indices
    }
    
    /**
     Creates an array of scenekit geometry element obejcts describing how to
     connect the geometry's vertices of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return An array of geometry elements.
     */
    public func makeGeometryElementsForNode(_ aiNode: aiNode,
                                            in aiScene: aiScene) -> [SCNGeometryElement] {
        
        var scnGeometryElements: [SCNGeometryElement] = []
        var indexOffset: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                let indexOffsetInt16Var = NSNumber(value: indexOffset).int16Value
                let nFacesIntVar = NSNumber(value: aiMesh.mNumFaces).intValue
                let indices = makeIndicesGeometryElement(forMeshIndex: Int(aiMeshIndex),
                                                         in: aiNode,
                                                         in: aiScene,
                                                         withIndexOffset: indexOffsetInt16Var,
                                                         nFaces: nFacesIntVar)
                if indices != nil {
                    scnGeometryElements.append(indices ?? SCNGeometryElement())
                }
                indexOffset += Int(aiMesh.mNumVertices)
                
            }
        }
        
        return scnGeometryElements
    }
    
    // MARK: - Make scenekit materials
    
    
    
    /**
     Updates a scenekit material's multiply property
     
     @param aiMaterial The assimp material
     @param material The scenekit material.
     */
    public func applyMultiplyProperty(for aiMaterial: UnsafePointer<aiMaterial>,
                                      with material: SCNMaterial) {
        
        var color = aiColor4D()
        color.r = 0.0
        color.g = 0.0
        color.b = 0.0
        let  matColor = aiGetMaterialColor(aiMaterial,
                                          AI_MATKEY_COLOR_TRANSPARENT.pKey,
                                          AI_MATKEY_COLOR_TRANSPARENT.type,
                                          AI_MATKEY_COLOR_TRANSPARENT.index,
                                          &color).rawValue
        if aiReturn_SUCCESS.rawValue == matColor {
            
            if color.r != 0 && color.g != 0 && color.b != 0 {
                
                let space = CGColorSpaceCreateDeviceRGB()
                let components: [CGFloat] = [CGFloat(color.r),
                                             CGFloat(color.g),
                                             CGFloat(color.b),
                                             CGFloat(color.a)]
                if let color = CGColor(colorSpace: space,
                                       components: components) {
                    material.multiply.contents = Color(cgColor: color)
                }
 
            }
            
        }
    }
    
    /**
     Creates an array of scenekit materials one for each mesh of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param path The path to the scene file to load.
     @return An array of scenekit materials.
     */
    public func makeMaterials(for aiNode: aiNode,
                              in aiScene: aiScene,
                              atPath path: String,
                              imageCache: AssimpImageCache) -> [SCNMaterial] {
        var scnMaterials: [SCNMaterial] = []
        let nodeAIMaterials = aiNode.getMaterials(from: aiScene)
        for var aiMaterial in nodeAIMaterials {
            print("Material name is \(aiMaterial.name)")
            let scnMaterial = SCNMaterial()
            scnMaterial.name = aiMaterial.name
            scnMaterial.loadContentsProperties(from: &aiMaterial,
                                               aiScene: aiScene,
                                               path: path,
                                               imageCache: imageCache)
            scnMaterial.loadMultiplyProperty(from: &aiMaterial)
            scnMaterial.loadBlendModeProperty(from: &aiMaterial)
            scnMaterial.loadCullModeProperty(from: &aiMaterial)
            scnMaterial.loadShininessProperty(from: &aiMaterial)
            scnMaterial.loadLightingModelProperty(from: &aiMaterial)
            scnMaterials.append(scnMaterial)
        }
        
        return scnMaterials
    }
    
    /**
     Creates a scenekit geometry to attach at the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The total number of vertices in the meshes of the node.
     @param path The path to the scene file to load.
     @return A new geometry.
     */
    public func makeSCNGeometry(fromAssimpNode aiNode: aiNode,
                                in aiScene: aiScene,
                                withVertices nVertices: Int,
                                atPath path: String,
                                imageCache: AssimpImageCache) -> SCNGeometry? {
        
        // make SCNGeometry with sources, elements and materials
        let scnGeometrySources = makeGeometrySources(for: aiNode,
                                                     in: aiScene,
                                                     withVertices: nVertices)
        if scnGeometrySources.count > 0 {
            var scnGeometry = SCNGeometry()
            let scnGeometryElements = makeGeometryElementsForNode(aiNode,
                                                                  in: aiScene)
            scnGeometry = SCNGeometry(sources: scnGeometrySources,
                                      elements: scnGeometryElements)
            let scnMaterials = makeMaterials(for: aiNode,
                                             in: aiScene,
                                             atPath: path,
                                             imageCache: imageCache)
            scnGeometry.materials = scnMaterials
            return scnGeometry
        } else {
            return nil
        }
    }
    
    // MARK: - Make scenekit cameras
    
    /**
     @name Make scenekit cameras
     */
    
    /**
     Creates a scenekit camera to attach at the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return A new scenekit camera.
     */
    public func makeSCNCamera(fromAssimpNode aiNode: aiNode, in aiScene: aiScene) -> SCNCamera? {
        
        let aiNodeName = aiNode.mName
        let nodeName = aiNodeName.stringValue()
        for i in 0 ..< aiScene.mNumCameras {
            
            if let aiCameraPointer = aiScene.mCameras[Int(i)] {
                
                let aiCamera = aiCameraPointer.pointee
                let aiCameraName = aiCamera.mName
                let cameraNodeName = aiCameraName.stringValue()
                if (nodeName == cameraNodeName) {
                    
                    let camera = SCNCamera()
                    camera.fieldOfView = CGFloat(aiCamera.mHorizontalFOV)
                    camera.zNear = Double(aiCamera.mClipPlaneNear)
                    camera.zFar = Double(aiCamera.mClipPlaneFar)
                    return camera
                    
                }
                
            }
        }
        
        return nil
    }
    
    // MARK: - Make scenekit skinner
    
    /**
     @name Make scenekit skinner
     */
    /**
     Finds the number of bones in the meshes of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return The number of bones.
     */
    public func findNumBones(in aiNode: aiNode, in aiScene: aiScene) -> Int {
        
        var nBones: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                nBones += Int(aiMesh.mNumBones)
                
            }
        }
        
        return nBones
    }
    
    /**
     Creates an array of bone names in the meshes of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return An array of bone names.
     */
    public func getBoneNames(forAssimpNode aiNode: aiNode, in aiScene: aiScene) -> [String] {
        
        var boneNames = [String]()
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                for j in 0 ..< aiMesh.mNumBones {
                    
                    if let aiBonePointer = aiMesh.mBones[Int(j)] {
                        
                        let aiBone = aiBonePointer.pointee
                        let name = aiBone.mName.stringValue()
                        boneNames.append(name as String)
                        
                    }
                    
                }
            }
        }
        
        return boneNames
    }
    
    /**
     Creates a dictionary of bone transforms where bone name is the key, for the
     meshes of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return A dictionary of bone transforms where bone name is the key.
     */
    public func getBoneTransforms(forAssimpNode aiNode: aiNode, in aiScene: aiScene) -> NSDictionary {
        
        let boneTransforms = NSMutableDictionary()
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                for j in 0 ..< aiMesh.mNumBones {
                    
                    if let aiBonePointer = aiMesh.mBones[Int(j)] {
                        
                        let aiBone = aiBonePointer.pointee
                        let name = aiBone.mName.stringValue()
                        let key = name
                        if boneTransforms.value(forKey: key) == nil {
                            
                            let aiNodeMatrix = aiBone.mOffsetMatrix
                            let glkBoneMatrix = GLKMatrix4.init(m: (
                                aiNodeMatrix.a1, aiNodeMatrix.b1, aiNodeMatrix.c1,
                                aiNodeMatrix.d1, aiNodeMatrix.a2, aiNodeMatrix.b2,
                                aiNodeMatrix.c2, aiNodeMatrix.d2, aiNodeMatrix.a3,
                                aiNodeMatrix.b3, aiNodeMatrix.c3, aiNodeMatrix.d3,
                                aiNodeMatrix.a4, aiNodeMatrix.b4, aiNodeMatrix.c4,
                                aiNodeMatrix.d4))
                            let scnMatrix = SCNMatrix4FromGLKMatrix4(glkBoneMatrix)
                            boneTransforms.setValue(scnMatrix, forKey: key)
                            
                        }
                        
                    }
                }
            }
        }
        
        return boneTransforms
    }
    
    /**
     Creates an array of bone transforms from a dictionary of bone transforms where
     bone name is the key.
     
     @param boneNames The array of bone names.
     @param boneTransforms The dictionary of bone transforms.
     @return An array of bone transforms
     */
    public func getTransformsForBones(_ boneNames: [String], fromTransforms boneTransforms: NSDictionary) -> [SCNMatrix4] {
        
        var transforms: [SCNMatrix4] = []
        for boneName in boneNames {
            if let value = boneTransforms.value(forKey: boneName) as? SCNMatrix4 {
                transforms.append(value)
            }
        }
        
        return transforms
    }
    
    /**
     Creates an array of scenekit bone nodes for the specified bone names.
     
     @param scene The scenekit scene.
     @param boneNames The array of bone names.
     @return An array of scenekit bone nodes.
     */
    public func findBoneNodes(in scnScene: SCNScene, forBones boneNames: [String]) -> [SCNNode] {
        
        var boneNodes: [SCNNode] = []
        for boneName in boneNames {
            if let boneNode = scnScene.rootNode.childNode(withName: boneName, recursively: true) {
                boneNodes.append(boneNode)
            }
        }
        
        return boneNodes
    }
    
    /**
     Find the root node of the skeleton from the specified bone nodes.
     
     @param boneNodes The array of bone nodes.
     @return The root node of the skeleton.
     */
    public func findSkeletonNode(fromBoneNodes boneNodes: [SCNNode]) -> SCNNode {
        
        var resultNode = SCNNode()
        let nodeDepths = NSMutableDictionary()
        var minDepth = -1
        for boneNode in boneNodes {
            
            let depth = findDepthOfNode(fromRoot: boneNode)
            if let boneNodeName = boneNode.name {
                
                print("bone with depth is (min depth): \(boneNodeName) -> \(depth) ( \(minDepth) )")
                
            }
            if minDepth == -1 || (depth <= minDepth) {
                minDepth = depth
                let key = "\(minDepth)"
                var minDepthNodes: NSMutableArray?
                if let value = nodeDepths.value(forKey: key) as? NSMutableArray {
                    minDepthNodes = value
                }
                if minDepthNodes == nil {
                    minDepthNodes = NSMutableArray()
                    nodeDepths.setValue(minDepthNodes, forKey: key)
                }
                if minDepthNodes != nil {
                    minDepthNodes!.add(boneNode)
                }
            }
            
        }
        let minDepthKey = "\(minDepth)"
        if let minDepthNodes = nodeDepths.value(forKey: minDepthKey) as? NSArray {
            
            print("min depth nodes are: \(String(describing: minDepthNodes))")
            
            if let skeletonRootNode = minDepthNodes[0] as? SCNNode {
                
                if minDepthNodes.count > 1 {
                    if skeletonRootNode.parent != nil {
                        resultNode = skeletonRootNode.parent!
                    } else {
                        resultNode = skeletonRootNode
                    }
                } else {
                    resultNode = skeletonRootNode
                }
                
            }
            
        }
        
        return resultNode
    }
    
    /**
     Finds the depth of the specified node from the scene's root node.
     
     @param node The scene node.
     @return The depth from the scene's root node.
     */
    public func findDepthOfNode(fromRoot node: SCNNode) -> Int {
        
        var depth: Int = 0
        var pNode = node
        while (pNode.parent != nil) {
            depth += 1
            pNode = pNode.parent!
        }
        
        return depth
    }
    
    /**
     Finds the maximum number of weights that influence the vertices in the meshes
     of the specified node.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @return The maximum influences or weights.
     */
    public func findMaxWeights(for aiNode: aiNode, in aiScene: aiScene) -> Int {
        
        var maxWeights: Int = 0
        
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                let meshWeights = NSMutableDictionary()
                for j in 0 ..< aiMesh.mNumBones {
                    
                    if let aiBonePointer = aiMesh.mBones[Int(j)] {
                        
                        let aiBone = aiBonePointer.pointee
                        for k in 0 ..< aiBone.mNumWeights {
                            
                            let aiVertexWeight = aiBone.mWeights[Int(k)]
                            let vertex = aiVertexWeight.mVertexId
                            if meshWeights.value(forKey: "\(vertex)") == nil {
                                meshWeights.setValue(Int(1), forKey: "\(vertex)")
                            } else {
                                if let weightCounts = meshWeights.value(forKey: "\(vertex)") as? Int {
                                    meshWeights.setValue(weightCounts + 1, forKey: "\(vertex)")
                                }
                            }
                            
                        }
                        
                    }
                    
                }
                
                // Find the vertex with most weights which is our max weights
                for j in 0 ..< aiMesh.mNumVertices {
                    
                    let vertex = j
                    if let weightsCount = meshWeights.value(forKey: "\(vertex)") as? Int {
                        
                        if weightsCount > maxWeights {
                            maxWeights = weightsCount
                        }
                        
                    }
                }
            }
        }
        
        return maxWeights
    }
    
    /**
     Creates a scenekit geometry source defining the influence of each bone on the
     positions of vertices in the geometry
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the node.
     @param maxWeights The maximum number of weights influencing each vertex.
     @return A new geometry source whose semantic property is boneWeights.
     */
    public func makeBoneWeightsGeometrySource(at aiNode: aiNode, in aiScene: aiScene, withVertices nVertices: Int, maxWeights: Int) -> SCNGeometrySource {
        
        let nodeGeometryWeights = UnsafeMutablePointer<Float>.allocate(capacity: nVertices * maxWeights)
        var weightCounter: Int = 0
        
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                let meshWeights = NSMutableDictionary()
                for j in 0 ..< aiMesh.mNumBones {
                    
                    if let aiBonePointer = aiMesh.mBones[Int(j)] {
                        
                        let aiBone = aiBonePointer.pointee
                        for k in 0 ..< aiBone.mNumWeights {
                            
                            let aiVertexWeight = aiBone.mWeights[Int(k)]
                            let vertex = aiVertexWeight.mVertexId
                            let weight = aiVertexWeight.mWeight
                            if meshWeights.value(forKey: "\(vertex)") == nil {
                                let weights = NSMutableArray()
                                weights.add(weight)
                                meshWeights.setValue(weights, forKey: "\(vertex)")
                            } else {
                                if let weights = meshWeights.value(forKey: "\(vertex)") as? NSMutableArray {
                                    weights.add(weight)
                                }
                            }
                            
                        }
                    }
                }
                
                // Add weights to the weights array for the entire node geometry
                for j in 0 ..< aiMesh.mNumVertices {
                    
                    let vertex = j
                    if let weights = meshWeights.value(forKey: "\(vertex)") as? NSMutableArray {
                        
                        let zeroWeights = maxWeights - weights.count
                        for weight in weights {
                            
                            if let weightFloatValue = weight as? NSNumber {
                                nodeGeometryWeights[weightCounter] = weightFloatValue.floatValue
                                weightCounter += 1
                            }
                            
                        }
                        for _ in 0 ..< zeroWeights {
                            nodeGeometryWeights[weightCounter] = Float(0.0)
                            weightCounter += 1
                        }
                        
                    }
                }
            }
        }
        
        print("weight counter \(weightCounter)")
        
        assert(weightCounter == nVertices * maxWeights)
        
        let dataLength = nVertices * maxWeights * MemoryLayout<Float>.size
        let data = NSData(bytes: nodeGeometryWeights, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<Float>.size
        let dataStride = maxWeights * bytesPerComponent
        let boneWeightsSource = SCNGeometrySource(data: data, semantic: .boneWeights, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: maxWeights, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        nodeGeometryWeights.deallocate()
        
        return boneWeightsSource
    }
    
    /**
     Creates a scenekit geometry source defining the mapping from bone indices in
     skeleton data to the skinner’s bones array
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param nVertices The number of vertices in the meshes of the node.
     @param maxWeights The maximum number of weights influencing each vertex.
     @param boneNames The array of unique bone names.
     @return A new geometry source whose semantic property is boneIndices.
     */
    public func makeBoneIndicesGeometrySource(at aiNode: aiNode, in aiScene: aiScene, withVertices nVertices: Int, maxWeights: Int, boneNames: [String]) -> SCNGeometrySource {
        
        print("Making bone indices geometry source: \(boneNames)")
        
        let nodeGeometryBoneIndices = UnsafeMutablePointer<CShort>.allocate(capacity: nVertices * maxWeights)
        var indexCounter: Int = 0
        for i in 0 ..< aiNode.mNumMeshes {
            
            let aiMeshIndex = aiNode.mMeshes[Int(i)]
            if let aiMeshPointer = aiScene.mMeshes[Int(aiMeshIndex)] {
                
                let aiMesh = aiMeshPointer.pointee
                let meshBoneIndices = NSMutableDictionary()
                for j in 0 ..< aiMesh.mNumBones {
                    
                    if let aiBonePointer = aiMesh.mBones[Int(j)] {
                        
                        let aiBone = aiBonePointer.pointee
                        for k in 0 ..< aiBone.mNumWeights {
                            
                            let aiVertexWeight = aiBone.mWeights[Int(k)]
                            let vertex = aiVertexWeight.mVertexId
                            let name = aiBone.mName
                            let boneName = name.stringValue()
                            if let boneIndex = boneNames.index(of: boneName) {
                                
                                if meshBoneIndices.value(forKey: "\(vertex)") == nil {
                                    let boneIndices = NSMutableArray()
                                    boneIndices.add(boneIndex)
                                    meshBoneIndices.setValue(boneIndices, forKey: "\(vertex)")
                                } else {
                                    if let boneIndices = meshBoneIndices.value(forKey: "\(vertex)") as? NSMutableArray {
                                        boneIndices.add(boneIndex)
                                    }
                                }
                                
                            }
                        }
                    }
                }
                
                // Add bone indices to the indices array for the entire node geometry
                for j in 0 ..< aiMesh.mNumVertices {
                    
                    let vertex = j
                    if let boneIndices = meshBoneIndices.value(forKey: "\(vertex)") as? NSMutableArray {
                        
                        let zeroIndices = maxWeights - boneIndices.count
                        for index in boneIndices {
                            if let boneIndex = index as? CShort {
                                nodeGeometryBoneIndices[indexCounter] = boneIndex
                                indexCounter += 1
                            }
                        }
                        for _ in 0 ..< zeroIndices {
                            nodeGeometryBoneIndices[indexCounter] = 0
                            indexCounter += 1
                        }
                        
                    }
                }
            }
        }
        
        assert(indexCounter == nVertices * maxWeights)
        
        let dataLength = nVertices * maxWeights * MemoryLayout<CShort>.size
        let data = NSData(bytes: nodeGeometryBoneIndices, length: dataLength) as Data
        let bytesPerComponent = MemoryLayout<CShort>.size
        let dataStride = maxWeights * bytesPerComponent
        let boneIndicesSource = SCNGeometrySource(data: data, semantic: .boneWeights, vectorCount: nVertices, usesFloatComponents: true, componentsPerVector: maxWeights, bytesPerComponent: bytesPerComponent, dataOffset: 0, dataStride: dataStride)
        
        nodeGeometryBoneIndices.deallocate()
        
        return boneIndicesSource
    }
    
    /**
     Builds a skeleton database of unique bone names and inverse bind bone
     transforms.
     
     When the scenekit scene is created from the assimp scene, a list of all bone
     names and a dictionary of bone transforms where each key is the bone name,
     is generated when parsing each node of the assimp scene.
     
     @param scene The scenekit scene.
     */
    public mutating func buildSkeletonDatabase(for scene: AssetImporterScene) {
        
        uniqueBoneNames = boneNames
        
        print("bone names \(uniqueBoneNames.count): \(uniqueBoneNames)")
        print("unique bone names \(uniqueBoneNames.count): \(uniqueBoneNames)")
        
        uniqueBoneNodes = findBoneNodes(in: scene, forBones: uniqueBoneNames)
        
        print("unique bone nodes \(uniqueBoneNodes.count): \(uniqueBoneNodes)")
        
        uniqueBoneTransforms = getTransformsForBones(uniqueBoneNames, fromTransforms: boneTransforms)
        
        print("unique bone transforms \(uniqueBoneTransforms.count): \(uniqueBoneTransforms)")
        
        skeleton = findSkeletonNode(fromBoneNodes: uniqueBoneNodes)
        scene.skeletonNode = self.skeleton
        
        print("skeleton bone is : \(skeleton)")
        
    }
    
    /**
     Creates a scenekit skinner for the specified node with visible geometry and
     skeleton information.
     
     @param aiNode The assimp node.
     @param aiScene The assimp scene.
     @param scene The scenekit scene.
     */
    public func makeSkinner(forAssimpNode aiNode: aiNode, in aiScene: aiScene, scnScene scene: AssetImporterScene) {
        
        let nBones: Int = findNumBones(in: aiNode, in: aiScene)
        let aiNodeName = aiNode.mName
        let nodeName = aiNodeName.stringValue()
        if nBones > 0 {
            
            let nVertices = findNumVertices(in: aiNode, in: aiScene)
            let maxWeights = findMaxWeights(for: aiNode, in: aiScene)
            
            print("Making Skinner for node: \(nodeName) vertices: \(nVertices) max-weights: \(maxWeights), nBones: \(nBones)")
            
            let boneWeights = makeBoneWeightsGeometrySource(at: aiNode, in: aiScene, withVertices: nVertices, maxWeights: maxWeights)
            let boneIndices = makeBoneIndicesGeometrySource(at: aiNode, in: aiScene, withVertices: nVertices, maxWeights: maxWeights, boneNames: uniqueBoneNames)
            
            if let node = scene.rootNode.childNode(withName: nodeName, recursively: true) {
                
                print(uniqueBoneNodes.count)
                print(uniqueBoneTransforms.count)
                let skinner = SCNSkinner(baseGeometry: node.geometry, bones: uniqueBoneNodes, boneInverseBindTransforms: uniqueBoneTransforms as [NSValue], boneWeights: boneWeights, boneIndices: boneIndices)
                skinner.skeleton = self.skeleton
                
                print(" assigned skinner \(skinner) skeleton: \(String(describing: skinner.skeleton))")
                
                node.skinner = skinner
                
            }
        }
        for i in 0 ..< aiNode.mNumChildren {
            if let aiChildNode = aiNode.mChildren[Int(i)]?.pointee {
                makeSkinner(forAssimpNode: aiChildNode, in: aiScene, scnScene: scene)
            }
        }
    }
    
    // MARK: - Make scenekit animations
    
    /**
     @name Make scenekit animations
     */
    
    /**
     Creates a dictionary of animations where each animation is a
     SCNAssimpAnimation, from each animation in the assimp scene.
     
     For each animation's channel which is a bone node, a CAKeyframeAnimation is
     created for each of position, orientation and scale. These animations are
     then stored in an SCNAssimpAnimation object, which holds the animation name and
     the keyframe animations.
     
     The animation name is generated by appending the file name with an animation
     index. The example of an animation name is walk-1 for the first animation in a
     file named walk.
     
     @param aiScene The assimp scene.
     @param scene The scenekit scene.
     @param path The path to the scene file to load.
     */
    public func createAnimations(from aiScene: aiScene, with scene: AssetImporterScene, atPath path: String) {
        
        print("Number of animations in scene: \(aiScene.mNumAnimations)")
        for i in 0 ..< aiScene.mNumAnimations {
            
            print("Animation data for animation at index: \(i)")
            
            if let aiAnimationPointer = aiScene.mAnimations[Int(i)] {
                
                let aiAnimation = aiAnimationPointer .pointee
                let animIndex = "-" + "\(i + 1)"
                let animName = (((((path as NSString).lastPathComponent) as NSString).deletingPathExtension) as NSString).appending(animIndex)
                
                print("Generated animation name: \(animName)")
                
                let currentAnimation = NSMutableDictionary()
                
                print("This animation \(animName) has \(aiAnimation.mNumChannels) channels with duration \(aiAnimation.mDuration) ticks per sec: \(aiAnimation.mTicksPerSecond)")
                
                var duration: Double
                if aiAnimation.mTicksPerSecond != 0 {
                    duration = aiAnimation.mDuration / aiAnimation.mTicksPerSecond
                } else {
                    duration = aiAnimation.mDuration
                }
                for j in 0 ..< aiAnimation.mNumChannels {
                    
                    if let aiNodeAnim: aiNodeAnim = aiAnimation.mChannels[Int(j)]?.pointee {
                        
                        let aiNodeName = aiNodeAnim.mNodeName
                        let name = aiNodeName.stringValue()
                        
                        print(" The channel \(name) has data for \(aiNodeAnim.mNumPositionKeys) position, \(aiNodeAnim.mNumRotationKeys) rotation, \(aiNodeAnim.mNumScalingKeys) scale keyframes")
                        
                        // create a lookup for all animation keys
                        let channelKeys = NSMutableDictionary()
                        
                        // create translation animation
                        let translationValues = NSMutableArray()
                        let translationTimes = NSMutableArray()
                        
                        for k in 0 ..< aiNodeAnim.mNumPositionKeys {
                            
                            let aiTranslationKey: aiVectorKey = aiNodeAnim.mPositionKeys[Int(k)]
                            let keyTime = aiTranslationKey.mTime
                            let aiTranslation = aiTranslationKey.mValue
                            translationTimes.add(Float(keyTime))
                            let pos = SCNVector3(aiTranslation.x, aiTranslation.y, aiTranslation.z)
                            translationValues.add(pos)
                            
                        }
                        
                        let translationKeyFrameAnim = CAKeyframeAnimation(keyPath: "position")
                        translationKeyFrameAnim.values = translationValues as? [Any]
                        translationKeyFrameAnim.keyTimes = translationTimes as? [NSNumber]
                        translationKeyFrameAnim.duration = duration
                        channelKeys.setValue(translationKeyFrameAnim, forKey: "position")
                        
                        // create rotation animation
                        let rotationValues = NSMutableArray()
                        let rotationTimes = NSMutableArray()
                        for k in 0 ..< aiNodeAnim.mNumRotationKeys {
                            
                            let aiQuatKey = aiNodeAnim.mRotationKeys[Int(k)]
                            let keyTime = aiQuatKey.mTime
                            let aiQuaternion = aiQuatKey.mValue
                            rotationTimes.add(Float(keyTime))
                            let quat = SCNVector4(aiQuaternion.x, aiQuaternion.y, aiQuaternion.z, aiQuaternion.w)
                            rotationValues.add(quat)
                            
                        }
                        let rotationKeyFrameAnim = CAKeyframeAnimation(keyPath: "orientation")
                        rotationKeyFrameAnim.values = rotationValues as? [Any]
                        rotationKeyFrameAnim.keyTimes = rotationTimes as? [NSNumber]
                        rotationKeyFrameAnim.duration = duration
                        channelKeys.setValue(rotationKeyFrameAnim, forKey: "orientation")
                        
                        // create scale animation
                        let scaleValues = NSMutableArray()
                        let scaleTimes = NSMutableArray()
                        for k in 0 ..< aiNodeAnim.mNumScalingKeys {
                            
                            let aiScaleKey = aiNodeAnim.mScalingKeys[Int(k)]
                            let keyTime = aiScaleKey.mTime
                            let aiScale = aiScaleKey.mValue
                            scaleTimes.add(Float(keyTime))
                            let scale = SCNVector3(aiScale.x, aiScale.y, aiScale.z)
                            scaleValues.add(scale)
                            
                        }
                        let scaleKeyFrameAnim = CAKeyframeAnimation(keyPath: "scale")
                        scaleKeyFrameAnim.values = scaleValues as? [Any]
                        scaleKeyFrameAnim.keyTimes = scaleTimes as? [NSNumber]
                        scaleKeyFrameAnim.duration = duration
                        channelKeys.setValue(scaleKeyFrameAnim, forKey: "scale")
                        
                        currentAnimation.setValue(channelKeys, forKey: name)
                        
                    }
                }
                
                let animation = AssetImporterAnimation(key: animName, frameAnims: currentAnimation)
                scene.animations.setValue(animation, forKey: animName)
            }
        }
    }
}

