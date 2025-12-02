-- ============================================================================
-- Cleanup: Remove Existing Objects
-- ============================================================================
-- Drop existing table and types to allow clean re-creation of the schema.
-- This ensures a fresh start for the lab exercise.
-- ============================================================================
DROP TABLE IF EXISTS players;
DROP TYPE IF EXISTS season_stats;
DROP TYPE IF EXISTS scoring_class;

-- ============================================================================
-- Dimensional Data Modeling: Complex Data Types and Cumulation Pattern
-- ============================================================================
-- This script demonstrates how to model player data using:
-- 1. Complex data types (composite types/structs)
-- 2. Array aggregation for historical data (cumulation pattern)
--
-- The cumulation pattern stores multiple seasons of statistics as an array
-- of structs within a single row, enabling efficient querying of a player's
-- entire career history without requiring joins or multiple rows per player.
-- ============================================================================

-- Inspect the source data structure to understand the input format

-- ============================================================================
-- Custom Composite Type: season_stats
-- ============================================================================
-- Defines a structured type to represent a single season's statistics.
-- This composite type (struct) groups related season metrics together.
--
-- Fields:
--   season: The season year/identifier
--   gp:     Games played in the season
--   pts:    Average points per game
--   reb:    Average rebounds per game
--   ast:    Average assists per game
-- ============================================================================
CREATE TYPE season_stats AS (
    season INTEGER,  -- Season identifier (e.g., 2023, 2024)
    gp INTEGER,      -- Games played
    pts REAL,        -- Points per game
    reb REAL,        -- Rebounds per game
    ast REAL         -- Assists per game
);

-- ============================================================================
-- Players Table: Cumulated Dimensional Model
-- ============================================================================
-- This table implements a cumulation pattern where:
-- - Player demographic information is stored once per player
-- - Historical season statistics are accumulated as an array of season_stats
-- - The current_season field tracks the most recent season in the array
--
-- Benefits:
--   - Single row per player (per current_season) instead of one row per season
--   - Efficient queries across a player's entire career without joins
--   - Array operations allow filtering/aggregation of historical seasons
--
-- Primary Key: (player_name, current_season)
--   - Allows tracking of player data across different time periods
--   - Supports scenarios where player data is updated incrementally
-- ============================================================================

-- ============================================================================
-- Custom Enum Type: scoring_class
-- ============================================================================
-- Defines a categorical classification for player scoring ability based on
-- points per game performance in the current season.
--
-- Classification Levels:
--   'bad':     <= 10 points per game
--   'average': 10-15 points per game
--   'good':    15-20 points per game
--   'star':    > 20 points per game
--
-- This derived attribute is recalculated during incremental loads based on
-- the most recent season's performance, enabling efficient filtering and
-- analysis of player tiers.
-- ============================================================================
CREATE TYPE scoring_class AS
    ENUM ('bad', 'average', 'good', 'star');







CREATE TABLE players (
    -- Player demographic information (relatively static)
    player_name TEXT,      -- Player's full name
    height TEXT,           -- Player's height
    college TEXT,          -- College/university attended
    country TEXT,          -- Country of origin
    draft_year TEXT,       -- Year drafted
    draft_round TEXT,      -- Draft round
    draft_number TEXT,     -- Draft pick number
    
    -- Cumulated historical data: array of season statistics
    -- Each element in the array represents one season's stats
    season_stats season_stats[],  -- Array of season_stats structs
    
    -- Derived attributes: Calculated based on current season performance
    scoring_class scoring_class,   -- Player tier classification based on points per game
                                  -- Recalculated during each incremental load
    
    -- Time-based tracking: Monitors player activity status
    years_since_last_active INTEGER,  -- Number of seasons since player last appeared
                                      -- Resets to 0 when new season data arrives
                                      -- Increments by 1 when no new data for a season
    
    -- Metadata for tracking
    current_season INTEGER,        -- Most recent season in season_stats array
    
    PRIMARY KEY (player_name, current_season)
);

-- ============================================================================
-- Data Exploration: Find Starting Point
-- ============================================================================
-- Identify the minimum season in the source data to determine where to begin
-- the incremental load process.
-- ============================================================================
SELECT MIN(season) FROM player_seasons;

-- ============================================================================
-- Incremental Load: SCD Type 2 with Array Cumulation Pattern
-- ============================================================================
-- This implements an idempotent, incremental load pattern that:
-- 1. Takes a snapshot of the current state (yesterday)
-- 2. Merges it with new incremental data (today)
-- 3. Cumulates season statistics into arrays
-- 4. Handles new players, existing players with new seasons, and unchanged players
--
-- Pattern: Incremental SCD (Slowly Changing Dimension) with cumulation
-- Idempotency: Can be safely re-run with the same data
--
-- CTEs:
--   yesterday: Snapshot of players table at current_season = 2000
--              Represents the "previous state" before processing new data
--   today:     New season data from player_seasons where season = 2001
--              Represents the "incremental data" to be merged
--
-- Join Strategy: FULL OUTER JOIN
--   - Left side only: New players (not in yesterday, appear in today)
--   - Both sides: Existing players with new season data
--   - Right side only: Players with no new data (preserved from yesterday)
--
-- Array Cumulation Logic:
--   - New players (y.season_stats IS NULL): Create array with first season
--   - Existing players (t.player_name IS NOT NULL): Append new season to array
--   - No new data: Preserve existing array unchanged
--
-- The || operator concatenates arrays, building cumulative history over time.
-- ============================================================================



INSERT INTO players
WITH yesterday AS (
    -- Snapshot of current state: all players with their cumulated stats up to season 2000
    SELECT * FROM players
    WHERE current_season = 2000
),
    today AS (
        -- Incremental data: new season 2001 statistics from source table
        SELECT * FROM player_seasons
        WHERE season = 2001
    )

SELECT 
    -- Player demographics: Use new data if available, otherwise preserve existing
    -- COALESCE ensures we get data from either 'today' (new players) or 'yesterday' (existing players)
    -- This handles all three cases from the FULL OUTER JOIN:
    --   1. New players (only in today): Use today's data
    --   2. Existing players (in both): Prefer today's data, fallback to yesterday
    --   3. Inactive players (only in yesterday): Use yesterday's data
    COALESCE(t.player_name, y.player_name) as player_name,
    COALESCE(t.height, y.height) as height,
    COALESCE(t.college, y.college) as college,
    COALESCE(t.country, y.country) as country,
    COALESCE(t.draft_year, y.draft_year) as draft_year,
    COALESCE(t.draft_round, y.draft_round) as draft_round,
    COALESCE(t.draft_number, y.draft_number) as draft_number,
    
    -- Array cumulation: Build or append to season_stats array
    -- ROW() constructor creates a composite type value matching season_stats structure
    -- ::season_stats casts the row to the season_stats composite type
    -- ARRAY[...] creates an array containing the season_stats struct
    -- || operator concatenates arrays (appends new element to existing array)
    CASE 
        -- New player: Create array with first season's stats
        -- Creates a single-element array containing the first season's statistics
        WHEN y.season_stats IS NULL 
        THEN ARRAY[ROW(
            t.season,   -- Season identifier
            t.gp,       -- Games played
            t.pts,      -- Points per game
            t.reb,      -- Rebounds per game
            t.ast       -- Assists per game
            )::season_stats] 
        -- Existing player with new season: Append new season to existing array
        -- Concatenates existing array with new single-element array
        -- Result: All historical seasons plus the new season
        WHEN t.player_name IS NOT NULL 
        THEN y.season_stats || ARRAY[ROW(
            t.season, 
            t.gp,
            t.pts, 
            t.reb, 
            t.ast
            )::season_stats]
        -- No new data: Preserve existing array unchanged
        -- Player had no activity this season, keep historical data as-is
        ELSE y.season_stats
    END as season_stats,
    
    -- Scoring Class Calculation: Derived attribute based on current season performance
    -- Logic: Recalculate if new season data exists, otherwise preserve existing classification
    CASE 
        -- New season data available: Recalculate scoring class based on current season points
        WHEN t.season IS NOT NULL THEN      
            CASE 
                WHEN t.pts > 20 THEN 'star'      -- Elite scorer: > 20 PPG
                WHEN t.pts > 15 THEN 'good'      -- Strong scorer: 15-20 PPG
                WHEN t.pts > 10 THEN 'average'   -- Average scorer: 10-15 PPG
                ELSE 'bad'                        -- Below average: <= 10 PPG
            END::scoring_class
        -- No new season data: Preserve existing classification
        ELSE y.scoring_class
    END as scoring_class,

    -- Years Since Last Active: Tracks player inactivity
    -- Logic: Reset to 0 if player has new season, otherwise increment counter
    CASE 
        -- Player has new season data: Reset counter (player is active)
        WHEN t.season IS NOT NULL THEN 0
        -- No new season data: Increment counter (player is inactive for another season)
        ELSE y.years_since_last_active + 1
    END as years_since_last_active,
    
    -- Update current_season: Use new season if available, otherwise increment
    -- If new season exists, use it; otherwise increment from previous season
    COALESCE(t.season, y.current_season + 1) as current_season

FROM today t
-- FULL OUTER JOIN ensures we capture all scenarios:
--   - Players only in 'today': New players entering the system
--   - Players in both: Existing players with new season data
--   - Players only in 'yesterday': Inactive players (no new data this season)
FULL OUTER JOIN yesterday y
ON t.player_name = y.player_name;

-- ============================================================================
-- Verification Query: Inspect Loaded Data
-- ============================================================================
-- Verify that the incremental load worked correctly by querying a specific player.
-- This shows the cumulated array structure with all seasons up to current_season = 2001.
-- ============================================================================

SELECT * FROM players
WHERE current_season = 2001
AND player_name = 'Michael Jordan';

-- ============================================================================
-- Analytical Query: Points Growth Ratio Analysis
-- ============================================================================
-- This query demonstrates how to analyze cumulated array data to calculate
-- career progression metrics. It identifies star players with the highest
-- growth in scoring from their first season to their most recent season.
--
-- Calculation:
--   Growth Ratio = Latest Season Points / First Season Points
--
-- Array Access Patterns:
--   - season_stats[CARDINALITY(season_stats)]: Accesses the last element
--     (most recent season) using array cardinality function
--   - season_stats[1]: Accesses the first element (first season) using
--     array index notation (1-based indexing)
--
-- Use Cases:
--   - Identify players who improved significantly over their career
--   - Find star players with the best career progression
--   - Analyze development trajectories
--
-- Filter: Only analyzes 'star' players (scoring_class = 'star') to focus
--         on elite performers and their career development patterns.
-- ============================================================================
SELECT 
    player_name,
    -- Calculate points growth ratio: latest season points / first season points
    -- Numerator: Latest season points (last element in array)
    --   - CARDINALITY(season_stats) returns the array length
    --   - season_stats[CARDINALITY(season_stats)] gets the last element
    --   - Cast to season_stats type and extract .pts field
    -- Denominator: First season points (first element in array)
    --   - season_stats[1] gets the first element (1-based indexing)
    --   - Cast to season_stats type and extract .pts field
    --   - Division by zero protection: Use 1 if first season had 0 points
    (season_stats[CARDINALITY(season_stats)]::season_stats).pts /
    CASE 
        WHEN (season_stats[1]::season_stats).pts = 0 THEN 1  -- Avoid division by zero
        ELSE (season_stats[1]::season_stats).pts  -- Use first season points as denominator
    END as points_growth_ratio
FROM players
WHERE current_season = 2001
AND scoring_class = 'star'  -- Filter to only analyze elite performers
ORDER BY points_growth_ratio DESC;  -- Show highest growth ratios first
