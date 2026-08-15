package com.swipy.feature.filters

sealed interface FilterCategoriesIntent {
    data object Refresh : FilterCategoriesIntent
}
