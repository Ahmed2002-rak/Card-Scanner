allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                android.compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }

        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    project.evaluationDependsOn(":app")

    // Fix for older plugins missing namespace or having package in manifest
    project.plugins.withId("com.android.library") {
        project.extensions.getByType<com.android.build.gradle.LibraryExtension>().apply {
            if (namespace == null) {
                namespace = when (project.name) {
                    "flutter_jailbreak_detection" -> "com.g123k.flutter_jailbreak_detection"
                    "device_info_plus" -> "dev.fluttercommunity.plus.device_info"
                    "flutter_secure_storage" -> "com.it_s_all_widgets.flutter_secure_storage"
                    "cloud_firestore" -> "io.flutter.plugins.firebase.cloudfirestore"
                    "cloud_functions" -> "io.flutter.plugins.firebase.functions"
                    "firebase_core" -> "io.flutter.plugins.firebase.core"
                    else -> null
                }
            }
        }
        
        // Remove package attribute from manifest to avoid conflicts with namespace
        project.tasks.matching { it.name.contains("process") && it.name.contains("Manifest") }.configureEach {
            doFirst {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    if (content.contains("package=")) {
                        val newContent = content.replace(Regex("package=\"[^\"]*\""), "")
                        manifestFile.writeText(newContent)
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
