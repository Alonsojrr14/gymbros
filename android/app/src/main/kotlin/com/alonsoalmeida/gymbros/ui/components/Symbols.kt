package com.alonsoalmeida.gymbros.ui.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Accessible
import androidx.compose.material.icons.filled.AccessibleForward
import androidx.compose.material.icons.filled.AccessibilityNew
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.DownhillSkiing
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FitnessCenter
import androidx.compose.material.icons.filled.Forest
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.IceSkating
import androidx.compose.material.icons.filled.MonitorHeart
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.NordicWalking
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Phishing
import androidx.compose.material.icons.filled.Pool
import androidx.compose.material.icons.filled.Rowing
import androidx.compose.material.icons.filled.Sailing
import androidx.compose.material.icons.filled.ScubaDiving
import androidx.compose.material.icons.filled.SelfImprovement
import androidx.compose.material.icons.filled.Snowboarding
import androidx.compose.material.icons.filled.Sports
import androidx.compose.material.icons.filled.SportsBaseball
import androidx.compose.material.icons.filled.SportsBasketball
import androidx.compose.material.icons.filled.SportsCricket
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.SportsFootball
import androidx.compose.material.icons.filled.SportsGolf
import androidx.compose.material.icons.filled.SportsGymnastics
import androidx.compose.material.icons.filled.SportsHandball
import androidx.compose.material.icons.filled.SportsHockey
import androidx.compose.material.icons.filled.SportsKabaddi
import androidx.compose.material.icons.filled.SportsMartialArts
import androidx.compose.material.icons.filled.SportsMma
import androidx.compose.material.icons.filled.SportsRugby
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.SportsTennis
import androidx.compose.material.icons.filled.SportsVolleyball
import androidx.compose.material.icons.filled.Stairs
import androidx.compose.material.icons.filled.Surfing
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Toys
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Waves
import androidx.compose.material.icons.filled.Whatshot
import androidx.compose.ui.graphics.vector.ImageVector
import com.alonsoalmeida.gymbros.domain.Attribute

/**
 * Equivalente Material de cada SF Symbol que o iOS usa nos tipos de treino (ios/Shared/WorkoutCatalog.swift) e nos
 * atributos. O Material não tem desenho para todos os esportes: nesses, o mais próximo. Sem equivalente: o haltere.
 */
object Symbols {
    fun of(symbol: String): ImageVector = when (symbol) {
        "figure.strengthtraining.traditional", "figure.strengthtraining.functional" -> Icons.Filled.FitnessCenter
        "figure.cross.training", "figure.highintensity.intervaltraining" -> Icons.Filled.Whatshot
        "figure.core.training" -> Icons.Filled.AccessibilityNew
        "figure.mixed.cardio" -> Icons.Filled.MonitorHeart
        "figure.elliptical", "figure.run", "figure.track.and.field" -> Icons.Filled.DirectionsRun
        "figure.stair.stepper", "figure.stairs", "figure.step.training" -> Icons.Filled.Stairs
        "figure.jumprope", "figure.gymnastics" -> Icons.Filled.SportsGymnastics
        "gamecontroller.fill" -> Icons.Filled.SportsEsports
        "figure.cooldown", "figure.flexibility", "figure.yoga", "figure.pilates", "figure.mind.and.body", "figure.taichi" -> Icons.Filled.SelfImprovement
        "figure.walk" -> Icons.Filled.DirectionsWalk
        "figure.hiking" -> Icons.Filled.Hiking
        "figure.roll" -> Icons.Filled.Accessible
        "figure.roll.runningpace", "figure.hand.cycling" -> Icons.Filled.AccessibleForward
        "figure.outdoor.cycle" -> Icons.Filled.DirectionsBike
        "figure.pool.swim", "figure.open.water.swim", "figure.water.fitness", "figure.waterpolo" -> Icons.Filled.Pool
        "figure.surfing" -> Icons.Filled.Surfing
        "oar.2.crossed", "figure.rower" -> Icons.Filled.Rowing
        "water.waves" -> Icons.Filled.Waves
        "water.waves.and.arrow.down" -> Icons.Filled.ScubaDiving
        "figure.soccer" -> Icons.Filled.SportsSoccer
        "figure.basketball" -> Icons.Filled.SportsBasketball
        "figure.volleyball" -> Icons.Filled.SportsVolleyball
        "figure.handball" -> Icons.Filled.SportsHandball
        "figure.american.football" -> Icons.Filled.SportsFootball
        "figure.rugby", "figure.australian.football" -> Icons.Filled.SportsRugby
        "figure.baseball", "figure.softball", "figure.bowling" -> Icons.Filled.SportsBaseball
        "figure.cricket" -> Icons.Filled.SportsCricket
        "figure.hockey", "figure.lacrosse", "figure.curling" -> Icons.Filled.SportsHockey
        "figure.tennis", "figure.table.tennis", "figure.squash", "figure.racquetball", "figure.badminton", "figure.pickleball" -> Icons.Filled.SportsTennis
        "figure.martial.arts" -> Icons.Filled.SportsMartialArts
        "figure.boxing", "figure.kickboxing" -> Icons.Filled.SportsMma
        "figure.wrestling", "figure.fencing" -> Icons.Filled.SportsKabaddi
        "figure.dance", "figure.socialdance", "figure.barre" -> Icons.Filled.MusicNote
        "snowflake", "figure.skiing.downhill" -> Icons.Filled.DownhillSkiing
        "figure.skiing.crosscountry" -> Icons.Filled.NordicWalking
        "figure.snowboarding" -> Icons.Filled.Snowboarding
        "figure.skating" -> Icons.Filled.IceSkating
        "figure.sailing" -> Icons.Filled.Sailing
        "figure.golf" -> Icons.Filled.SportsGolf
        "figure.archery" -> Icons.Filled.TrackChanges
        "figure.fishing" -> Icons.Filled.Phishing
        "figure.hunting" -> Icons.Filled.Forest
        "figure.equestrian.sports" -> Icons.Filled.Pets
        "figure.play" -> Icons.Filled.Toys
        "figure.climbing" -> Icons.Filled.Terrain
        "figure.disc.sports" -> Icons.Filled.Sports
        else -> Icons.Filled.FitnessCenter
    }

    /** dumbbell.fill, heart.fill, bolt.fill, sparkles */
    fun of(a: Attribute): ImageVector = when (a) {
        Attribute.FORCA -> Icons.Filled.FitnessCenter
        Attribute.RESISTENCIA -> Icons.Filled.Favorite
        Attribute.AGILIDADE -> Icons.Filled.Bolt
        Attribute.TECNICA -> Icons.Filled.AutoAwesome
    }
}
