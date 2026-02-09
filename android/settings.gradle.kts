pluginManagement {
    repositories {
        maven {
            url = uri("https://dl.google.com/dl/android/maven2/")
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven {
            url = uri("https://dl.google.com/dl/android/maven2/")
        }
        mavenCentral()
    }
}

rootProject.name = "Macroid"
include(":app")
