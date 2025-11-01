WITH PneumoniaCohort AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        ie.stay_id,
        ie.los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON ad.hadm_id = ie.hadm_id AND p.subject_id = ie.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 55 AND 65
        -- Ensure the patient had a pneumonia diagnosis during this admission
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.hadm_id = ad.hadm_id
                AND di.icd_version = 10 -- Assuming ICD-10 for current pneumonia diagnoses
                -- Common ICD-10 codes for pneumonia (J12-J18)
                AND (
                    LEFT(di.icd_code, 3) BETWEEN 'J12' AND 'J16'
                    OR LEFT(di.icd_code, 3) = 'J18'
                )
        )
),
-- Step 2: Simulate/Assign an "instability score" for each patient in the cohort.
-- Note: The "instability score" is hypothetical and not found in MIMIC-IV.
-- For demonstration, a stable pseudo-random score between 0 and 100 is generated for each unique ICU stay.
-- This is a critical assumption as the actual score definition is not provided.
CohortWithSimulatedScores AS (
    SELECT
        pc.subject_id,
        pc.hadm_id,
        pc.stay_id,
        pc.los,
        pc.hospital_expire_flag,
        -- Generate a pseudo-random score between 0 and 100 for each unique stay_id.
        -- FARM_FINGERPRINT provides a consistent hash for a given input, ensuring the score for a stay_id
        -- remains the same across different executions of the query (given the same data).
        MOD(ABS(FARM_FINGERPRINT(CAST(pc.stay_id AS STRING))), 101) AS instability_score
    FROM
        PneumoniaCohort pc
),
-- Step 3a: Prepare all scores (simulated + the specific score of 60) for percentile calculation.
AllScoresForPercentile AS (
    -- Simulated scores from our cohort
    SELECT instability_score FROM CohortWithSimulatedScores
    UNION ALL
    -- The specific instability score of 'my patient' as mentioned in the question
    SELECT 60 AS instability_score
),
-- Step 3b: Calculate percentile rank for all scores
RankedScores AS (
    SELECT
        instability_score,
        -- PERCENT_RANK() returns a value from 0 to 1, representing the rank of a row
        -- relative to the other values in the window partition.
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank
    FROM AllScoresForPercentile
),
-- Step 4: Add decile rank to the cohort for identifying the most unstable group.
CohortWithRanks AS (
    SELECT
        cws.subject_id,
        cws.hadm_id,
        cws.stay_id,
        cws.los,
        cws.hospital_expire_flag,
        cws.instability_score,
        -- NTILE(10) divides the ordered set into 10 groups.
        -- ORDER BY instability_score DESC ensures that higher scores are in lower-numbered deciles (i.e., decile 1 is the most unstable).
        NTILE(10) OVER (ORDER BY cws.instability_score DESC) AS decile_rank
    FROM
        CohortWithSimulatedScores cws
)
-- Final SELECT statements to present the results as requested.
SELECT
    'Percentile of score 60' AS metric_description,
    ROUND(MAX(rs.percentile_rank) * 100, 2) AS percentile_value,
    NULL AS average_icu_los_days,
    NULL AS hospital_mortality_rate_percent
FROM
    RankedScores rs
WHERE
    rs.instability_score = 60
    AND rs.percentile_rank IS NOT NULL -- Ensure we pick the percentile for the '60' entry
GROUP BY
    metric_description

UNION ALL

SELECT
    'Metrics for Most Unstable Decile' AS metric_description,
    NULL AS percentile_value,
    ROUND(AVG(cwr.los), 2) AS average_icu_los_days,
    -- AVG(hospital_expire_flag) directly gives the proportion of deaths (0/1 values), multiply by 100 for percentage.
    ROUND(AVG(cwr.hospital_expire_flag) * 100, 2) AS hospital_mortality_rate_percent
FROM
    CohortWithRanks cwr
WHERE
    cwr.decile_rank = 1;