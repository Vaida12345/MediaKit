# ``MediaKit``

A collection of extended functionalities to the media frameworks. 

@Metadata {
    @PageColor(red)
    
    @SupportedLanguage(swift)
    
    @Available(macOS,    introduced: 13.0)
    @Available(iOS,      introduced: 16.0)
    @Available(watchOS,  introduced: 9.0)
    @Available(tvOS,     introduced: 16.0)
    @Available(visionOS, introduced: 1.0)
}

## Overview

The framework aims to provide additional methods for the structures defined within `PDFKit` and `AVFoundation`.


## Getting Started

`MediaKit` uses [Swift Package Manager](https://www.swift.org/documentation/package-manager/) as its build tool. If you want to import in your own project, it's as simple as adding a `dependencies` clause to your `Package.swift`:
```swift
dependencies: [
    .package(name: "MediaKit", 
             path: "~/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/MediaKit")
]
```
and then adding the appropriate module to your target dependencies.

### Using Xcode Package support

You can add this framework as a dependency to your Xcode project by clicking File -> Swift Packages -> Add Package Dependency. The package is located at:
```
~/Library/Mobile Documents/com~apple~CloudDocs/DataBase/Projects/Packages/MediaKit
```


## Topics

### Core

- <doc:AVAsset>
- <doc:PDF>