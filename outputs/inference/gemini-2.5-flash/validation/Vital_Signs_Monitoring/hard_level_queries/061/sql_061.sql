WITH acs_icustay_cohort AS (
    -- Step 1: Identify the target patient cohort
    -- Female ICU patients aged 49-59 with an ACS diagnosis during their hospital admission
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id,
        ic.stay_id,
        ad.hospital_expire_flag,
        ic.intime,
        ic.outtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON ad.subject_id = ic.subject_id AND ad.hadm_id = ic.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 49 AND 59
        AND EXISTS (
            -- Subquery to check for ACS ICD-10 diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.icd_version = 10 -- Assuming ICD-10 for the specified codes
                AND di.icd_code IN (
                    'I200', 'I210', 'I211', 'I212', 'I213', 'I214', 'I219', -- Unstable angina, various MIs
                    'I220', 'I221', 'I228', 'I229',                           -- Subsequent MIs
                    'I240'                                                 -- Coronary thrombosis not resulting in MI
                )
        )
),
cohort_with_scores_and_los AS (
    -- Step 2: Simulate the "first-24h composite vital instability score" and calculate LOS
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.hospital_expire_flag,
        -- Simulate the composite vital instability score (deterministic for each stay_id, range 1-100)
        MOD(FARM_FINGERPRINT(CAST(c.stay_id AS STRING)), 100) + 1 AS composite_score,
        -- Calculate ICU length of stay in days
        DATE_DIFF(c.outtime, c.intime, DAY) AS icu_los_days
    FROM
        acs_icustay_cohort c
    WHERE
        c.outtime IS NOT NULL AND c.intime IS NOT NULL -- Ensure valid LOS calculation
),
percentile_and_decile_ranks AS (
    -- Step 3: Calculate percentile ranks and assign decile groups based on the simulated score
    SELECT
        s.subject_id,
        s.hadm_id,
        s.stay_id,
        s.hospital_expire_flag,
        s.composite_score,
        s.icu_los_days,
        -- Calculate overall percentile rank (0 to 1) for each score
        PERCENT_RANK() OVER (ORDER BY s.composite_score ASC) AS raw_percent_rank,
        -- Assign decile groups, with NTILE(10) ordered DESC so '1' is the top decile (highest scores)
        NTILE(10) OVER (ORDER BY s.composite_score DESC) AS decile_group
    FROM
        cohort_with_scores_and_los s
)
-- Final result: Combine the percentile of score 70 and the metrics for the top decile
SELECT
    -- Part 1: Calculate the percentile of a composite score of 70
    -- This calculates the percentage of individuals in the cohort whose score is <= 70.
    (COUNTIF(c.composite_score <= 70) * 100.0) / COUNT(c.composite_score) AS percentile_of_70,

    -- Part 2: Calculate mean ICU LOS and hospital mortality for the top decile
    (SELECT
        AVG(pr.icu_los_days)
    FROM
        percentile_and_decile_ranks pr
    WHERE
        pr.decile_group = 1 -- Top decile (highest scores)
    ) AS mean_icu_los_days_top_decile,

    (SELECT
        AVG(pr.hospital_expire_flag) * 100
    FROM
        percentile_and_decile_ranks pr
    WHERE
        pr.decile_group = 1 -- Top decile (highest scores)
    ) AS hospital_mortality_percent_top_decile
FROM
    cohort_with_scores_and_los c;