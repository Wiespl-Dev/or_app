allprojects {
    repositories {
        google()
        mavenCentral()
        // Appodeal repository — hosts com.gemalto.jp2:jp2-android
        maven { url = uri("https://artifactory.appodeal.com/appodeal-public/") }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    project.layout.buildDirectory.set(newBuildDir.dir(project.name))
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}