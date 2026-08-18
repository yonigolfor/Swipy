//
//  DemoLanguageService.swift
//  Swipy
//
//  DEMO BRANCH ONLY — long-press "Device" on the Filters screen to flip the app's
//  preferred language between English and Hebrew, then relaunch so it takes effect.
//  Delete this file (and its one call site in SmartFiltersView.swift) before merging
//  back to main.
//

import Foundation

/// `AppleLanguages` is the standard, documented UserDefaults key iOS reads to decide
/// which of the app's own bundled `.lproj` folders `String(localized:)`/`NSLocalizedString`
/// resolve against — but only at process launch, it's not observed live. So this writes
/// the override and then force-quits; the user re-opens the app (from Xcode or the home
/// screen) and it comes up fully in the new language, no per-string plumbing needed.
enum DemoLanguageService {
    static func toggleLanguage() {
        let current = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first ?? "en"
        let next = current.hasPrefix("he") ? "en" : "he"
        UserDefaults.standard.set([next], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        print("[Demo] language set to '\(next)' — relaunch the app to see it")
        exit(0)
    }
}
