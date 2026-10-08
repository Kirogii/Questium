plugins {
    id("mihon.library")
}

android {
    namespace = "exh.yakuyomi.upscale"
}

dependencies {
    implementation(libs.onnxruntime.android)
}
