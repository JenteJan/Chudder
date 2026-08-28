package uk.jentejan.chudder.utility

val String.capitalize: String
    get() = this.mapIndexed { index, char -> if (index == 0) char.uppercase() else char.lowercase() }
        .joinToString(separator = "")