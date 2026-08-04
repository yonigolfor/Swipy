// Convention plugins module — houses AndroidFeatureConventionPlugin (see
// android/CLAUDE.md "Project Architecture & Directory Layout") so Compose/Hilt/lint
// setup is composed once here, not copy-pasted into every feature module's build file.
plugins {
    `kotlin-dsl`
}
