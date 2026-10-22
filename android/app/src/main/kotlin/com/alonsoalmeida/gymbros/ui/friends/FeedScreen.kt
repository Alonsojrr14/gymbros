package com.alonsoalmeida.gymbros.ui.friends

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.People
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.alonsoalmeida.gymbros.domain.home.HomeData
import com.alonsoalmeida.gymbros.ui.components.GMEmptyState
import com.alonsoalmeida.gymbros.ui.components.GMIconButton
import com.alonsoalmeida.gymbros.ui.components.GMScreen
import com.alonsoalmeida.gymbros.ui.components.PersonAvatar

/**
 * Aba Feed (FriendsFeed.swift `UnifiedFeedView`): o botão de Amigos no topo. Os posts (seus e dos amigos), as histórias
 * dos bros e o ranking da semana chegam com as ligas, que são de onde vêm os check-ins.
 */
@Composable
fun FeedScreen(home: HomeData, vm: FriendsViewModel, onSoon: (String) -> Unit) {
    var friendsOpen by remember { mutableStateOf(false) }
    val state by vm.state.collectAsStateValue()
    LaunchedEffect(Unit) { vm.refresh(home) }
    GMScreen(
        "Feed",
        bottomInset = 120.dp,
        leading = { PersonAvatar(home.trainerName, photo = home.profilePhoto) },
        trailing = { GMIconButton(Icons.Filled.People, "Amigos", { friendsOpen = true }) },
    ) {
        GMEmptyState(
            Icons.Filled.Group,
            if (state.friends.isEmpty()) "Sem amigos ainda" else "Nada por aqui",
            if (state.friends.isEmpty()) "Adicione amigos no canto de cima para ver os treinos deles aqui."
            else "Os treinos que você e os seus amigos postarem aparecem aqui. Os posts chegam no Android junto com as ligas.",
            Modifier.padding(top = 40.dp),
        )
    }
    FriendsScreen(friendsOpen, home, vm, onDismiss = { friendsOpen = false }, onSoon = onSoon)
}
