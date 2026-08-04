package com.swipy.data.mediastore

import com.swipy.domain.repository.PhotoRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
internal abstract class MediaStoreDataModule {

    @Binds
    abstract fun bindPhotoRepository(impl: MediaStorePhotoRepository): PhotoRepository
}
