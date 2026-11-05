package com.sellwild.sample

/** One slot on the Ads screen: its title, its fixed size in dp, and its e2e ids. */
data class AdSlotSpec(
    val title: String,
    val detail: String,
    val width: Int,
    val height: Int,
    val id: String,
    val sizeId: String,
)
