<p align="center">
    <img src="Media/AssetImportKit.png", width="844">
</p>

[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

**AssetImportKit** is a cross platform library (macOS, iOS) that coverts the files supported by [`Assimp`](https://github.com/assimp/assimp) to [`SceneKit`](https://developer.apple.com/reference/scenekit) scenes.

<p align="center">
    <img src="Media/AssetImportKit_Demonstration.png", width="818">
</p>

## Features

AssetImportKit allows you to import ***Assimp supported file formats*** directly in SceneKit at runtime.
The library supports:
* Geometry
* Materials (with color, embedded textures and external textures)
* Cameras and
* Skeletal animations.
* Serialization to `.scn` format

#### Supported file formats ####

AssetImportKit supports the following file formats:
3D, 3DS, 3MF, AC, AC3D, ACC, AMJ, ASE, ASK, B3D, BLEND (Blender), BVH, COB, CMS, DAE/Collada, DXF, ENFF, FBX, glTF 1.0 + GLB, glTF 2.0, HMB, IFC-STEP, IRR / IRRMESH, LWO, LWS, LXO, MD2, MD3, MD5, MDC, MDL, MESH / MESH.XML, MOT, MS3D, NDO, NFF, OBJ, OFF, OGEX, PLY, PMX, PRJ, Q3O, Q3S, RAW, SCN, SIB, SMD, STL, STP, TER, UC, VTA, X, X3D, XGL, ZGL.

## Demos

This repository includes 2 small demos for macOS and iOS.

<a href="3DViewer/README.md"><img src="Media/iOS Example App.png" width=50%></a><a href="SceneKitAssetImport/README.md"><img src="Media/macOS Example App.png" width=50%></a>

## Requirements

- Xcode 10 or later
- Swift 4.2
- iOS 11.3 or later
- macOS 10.13 or later

## Installation via `CocoaPods`

There are two ways to install `AssetImportKit` via `CocoaPods`:

* for development purposes:
  ```Ruby
  pod 'AssetImportKit/Universal'
  ```
  or just
  ```Ruby
  pod 'AssetImportKit'
  ```
  > In this case `AssetImportKit.framework` will contain `ARM64` and `x86_64` architectures needed for `Generic Device` and `Simulator` targets respectively.

* for release purposes:
  ```Ruby
  pod 'AssetImportKit/ARM64'
  ```
  > In this case `AssetImportKit.framework` will contain only `ARM64` architecture needed for uploading to the `AppStore`.

## Manual Installation

In order to install `AssetImportKit` manually please read the [`How-to-Install`](HowToInstall.md) guide.

## Usage

```Swift
/// Create container node
var modelContainerNode = SCNNode()
/// Create AssetImporter
let assetImporter = AssetImporter()
/// Import Scene
guard let importedScene = assetImporter.importScene(filePath, postProcessFlags: [.defaultQuality]),
let modelScene = importedScene.modelScene else { return }
/// Move child nodes from imported scene to container node
modelScene.rootNode.childNodes.forEach { modelContainerNode.addChildNode($0) }
sceneView.scene?.rootNode.addChildNode(modelContainerNode)
```

Note for `iOS` builds: if you are developing an `iOS` application, set the `Enable Bitcode` under `Build Settings->Build Options` of your target to `NO`.

## Author

| [<img src="https://avatars1.githubusercontent.com/u/8983647?s=460&amp;v=4" width="120px;"/>](https://github.com/eugenebokhan)   | [Eugene Bokhan](https://github.com/eugenebokhan)<br/><br/><sub>iOS Software Engineer</sub><br/> [![Twitter][1.1]][1] [![Github][2.1]][2] [![LinkedIn][3.1]][3]|
| - | :- |

[1.1]: http://i.imgur.com/wWzX9uB.png (twitter icon without padding)
[2.1]: http://i.imgur.com/9I6NRUm.png (github icon without padding)
[3.1]: https://www.kingsfund.org.uk/themes/custom/kingsfund/dist/img/svg/sprite-icon-linkedin.svg (linkedin icon)

[1]: https://twitter.com/eugenebokhan
[2]: https://github.com/eugenebokhan
[3]: https://www.linkedin.com/in/eugenebokhan/

## License

[AssetImportKit's license](LICENSE) is based on 3-clause BSD-License.
