package com.swipy.data.datastore

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.swipy.domain.repository.CategoryCountCacheRepository
import com.swipy.domain.repository.OnboardingStateRepository
import com.swipy.domain.repository.PhotoStateRepository
import com.swipy.domain.repository.SwipeQuotaRepository
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

private val Context.swipyDataStore: DataStore<Preferences> by preferencesDataStore(name = "swipy_prefs")

@Module
@InstallIn(SingletonComponent::class)
internal object DataStoreProvidesModule {

    @Provides
    @Singleton
    fun providePreferencesDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        context.swipyDataStore
}

@Module
@InstallIn(SingletonComponent::class)
internal abstract class DataStoreBindsModule {

    @Binds
    abstract fun bindPhotoStateRepository(impl: DataStorePhotoStateRepository): PhotoStateRepository

    @Binds
    abstract fun bindCategoryCountCacheRepository(
        impl: DataStoreCategoryCountCacheRepository,
    ): CategoryCountCacheRepository

    @Binds
    abstract fun bindOnboardingStateRepository(impl: DataStoreOnboardingStateRepository): OnboardingStateRepository

    @Binds
    abstract fun bindSwipeQuotaRepository(impl: DataStoreSwipeQuotaRepository): SwipeQuotaRepository
}
