#!/usr/bin/env swift
import CoreGraphics

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    print("usage: window-id-by-pid.swift <pid>")
    exit(1)
}

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for window in info {
    if (window[kCGWindowOwnerPID as String] as? Int32) == pid,
       let number = window[kCGWindowNumber as String] as? Int {
        print(number)
    }
}
