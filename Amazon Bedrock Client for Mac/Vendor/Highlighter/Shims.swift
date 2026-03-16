/*
 *  Shims.swift
 *  Vendored from HighlighterSwift (MIT License)
 *  Copyright 2026, Tony Smith
 *  Copyright 2016, Juan-Pablo Illanes
 */

#if os(macOS)
import AppKit
public typealias HRColor = NSColor
public typealias HRFont  = NSFont
#else
import UIKit
public typealias HRColor = UIColor
public typealias HRFont  = UIFont
#endif

public typealias AttributedStringKey = NSAttributedString.Key

#if os(macOS)
public typealias TextStorageEditActions = NSTextStorageEditActions
#else
public typealias TextStorageEditActions = NSTextStorage.EditActions
#endif
