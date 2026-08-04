package com.swipy.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.swipy.domain.model.FilterCategory
import com.swipy.domain.model.PhotoItem
import com.swipy.domain.usecase.GetCategoryCountUseCase
import com.swipy.domain.usecase.GetPhotoStackPageUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MainUiState(
    val isLoading: Boolean = false,
    val photos: List<PhotoItem> = emptyList(),
    val totalCount: Int = 0,
)

/**
 * Bring-up-only ViewModel proving the DI graph resolves end-to-end (:app -> :domain use
 * cases -> :data:mediastore repository). Not the eventual PhotoStackViewModel — that lives
 * in :feature:swipe per android/CLAUDE.md "Architecture" and owns the full MVI surface
 * (StateFlow<PhotoStackUiState> + sealed PhotoStackIntent), which this bring-up screen
 * intentionally does not attempt to replicate.
 */
@HiltViewModel
class MainViewModel @Inject constructor(
    private val getPhotoStackPageUseCase: GetPhotoStackPageUseCase,
    private val getCategoryCountUseCase: GetCategoryCountUseCase,
) : ViewModel() {

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()

    fun loadPhotos() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            val page = getPhotoStackPageUseCase(FilterCategory.All, offset = 0, limit = 30)
            val totalCount = getCategoryCountUseCase(FilterCategory.All)
            _uiState.update { it.copy(isLoading = false, photos = page, totalCount = totalCount) }
        }
    }
}
