package com.swipy.data.billing

import com.swipy.domain.repository.PremiumRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
internal abstract class BillingDataModule {

    @Binds
    abstract fun bindPremiumRepository(impl: BillingManager): PremiumRepository
}
