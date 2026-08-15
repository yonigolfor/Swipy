package com.swipy.data.vision

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.swipy.domain.repository.BlurBurstAnalysisRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Qualifier
import javax.inject.Singleton

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class BlurVerdictsStore

@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class ImageHashesStore

private val Context.blurVerdictsDataStore: DataStore<Preferences> by preferencesDataStore(name = "blur_verdicts_cache")
private val Context.imageHashesDataStore: DataStore<Preferences> by preferencesDataStore(name = "image_hashes_cache")

@Module
@InstallIn(SingletonComponent::class)
internal object VisionDataProvidesModule {

    @Provides
    @Singleton
    @BlurVerdictsStore
    fun provideBlurVerdictsDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        context.blurVerdictsDataStore

    @Provides
    @Singleton
    @ImageHashesStore
    fun provideImageHashesDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        context.imageHashesDataStore
}

@Module
@InstallIn(SingletonComponent::class)
internal abstract class VisionDataBindsModule {

    @Binds
    abstract fun bindBlurBurstAnalysisRepository(
        impl: BlurBurstAnalysisRepositoryImpl,
    ): BlurBurstAnalysisRepository
}
