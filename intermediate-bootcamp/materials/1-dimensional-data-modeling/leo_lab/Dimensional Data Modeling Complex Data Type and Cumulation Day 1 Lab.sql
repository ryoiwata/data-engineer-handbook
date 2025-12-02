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
SELECT * FROM player_seasons;

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
    COALESCE(t.player_name, y.player_name) as player_name,
    COALESCE(t.height, y.height) as height,
    COALESCE(t.college, y.college) as college,
    COALESCE(t.country, y.country) as country,
    COALESCE(t.draft_year, y.draft_year) as draft_year,
    COALESCE(t.draft_round, y.draft_round) as draft_round,
    COALESCE(t.draft_number, y.draft_number) as draft_number,
    
    -- Array cumulation: Build or append to season_stats array
    CASE 
        -- New player: Create array with first season's stats
        WHEN y.season_stats IS NULL 
        THEN ARRAY[ROW(
            t.season, 
            t.gp,
            t.pts, 
            t.reb, 
            t.ast
            )::season_stats] 
        -- Existing player with new season: Append new season to existing array
        WHEN t.player_name IS NOT NULL 
        THEN y.season_stats || ARRAY[ROW(
            t.season, 
            t.gp,
            t.pts, 
            t.reb, 
            t.ast
            )::season_stats]
        -- No new data: Preserve existing array
        ELSE y.season_stats
    END as season_stats,
    
    -- Update current_season: Use new season if available, otherwise increment
    COALESCE(t.season, y.current_season + 1) as current_season

FROM today t
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
-- Array Unnesting Pattern: Query Individual Seasons
-- ============================================================================
-- Demonstrates how to query the cumulated array data at the season level.
-- This pattern is useful when you need to analyze individual seasons rather than
-- the entire player record.
--
-- Process:
--   1. UNNEST(season_stats): Expands the array into individual rows
--      Each array element becomes a separate row
--   2. Cast to season_stats type: Ensures proper type handling
--   3. (season_stats::season_stats).*: Expands the composite type fields
--      This extracts all fields (season, gp, pts, reb, ast) as separate columns
--
-- Result: One row per season per player, with all season statistics as columns
-- ============================================================================
WITH unnested AS (
    -- Step 1: Unnest the array - each season_stats element becomes a row
    SELECT player_name,
           UNNEST(season_stats)::season_stats as season_stats
    FROM players
    WHERE current_season = 2001
)
-- Step 2: Expand the composite type to show all fields as columns
SELECT player_name,
       (season_stats::season_stats).*  -- Expands to: season, gp, pts, reb, ast
FROM unnested


