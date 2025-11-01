WITH cohort_filtered AS (
    -- Step 1: Identify male ICU patients aged 84-94 with an ischemic stroke diagnosis
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id,
        ic.stay_id,
        ic.intime,
        ic.outtime,
        ic.los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic ON ad.hadm_id = ic.hadm_id AND p.subject_id = ic.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON ad.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 84 AND 94
        AND (
            (diag.icd_version = 9 AND (
                diag.icd_code LIKE '433.%' OR  -- Occlusion of precerebral arteries (e.g., 433.11 for carotid artery with infarction)
                diag.icd_code LIKE '434.%' OR  -- Occlusion of cerebral arteries (e.g., 434.91 for unspecified artery with infarction)
                diag.icd_code = '436'         -- Acute, but ill-defined, cerebrovascular disease (often used for ischemic stroke)
            ))
            OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%') -- Cerebral infarction (e.g., I63.9 for cerebral infarction, unspecified)
        )
),
raw_vital_scores AS (
    -- Step 2: Calculate instability points for each vital sign measurement within the first 72 hours
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        -- Calculate instability points for each vital sign based on deviation from normal ranges
        CASE ce.itemid
            -- Heart Rate (itemid: 220045). Normal: 60-100 bpm. +1 point per 10 bpm deviation.
            WHEN 220045 THEN
                CASE
                    WHEN ce.valuenum < 60 THEN CEIL((60 - ce.valuenum) / 10.0)
                    WHEN ce.valuenum > 100 THEN CEIL((ce.valuenum - 100) / 10.0)
                    ELSE 0
                END
            -- Non Invasive Blood Pressure Systolic (itemid: 220179). Normal: 90-140 mmHg. +1 point per 10 mmHg deviation.
            WHEN 220179 THEN
                CASE
                    WHEN ce.valuenum < 90 THEN CEIL((90 - ce.valuenum) / 10.0)
                    WHEN ce.valuenum > 140 THEN CEIL((ce.valuenum - 140) / 10.0)
                    ELSE 0
                END
            -- Respiratory Rate (itemid: 220210). Normal: 12-20 bpm. +1 point per 5 bpm deviation.
            WHEN 220210 THEN
                CASE
                    WHEN ce.valuenum < 12 THEN CEIL((12 - ce.valuenum) / 5.0)
                    WHEN ce.valuenum > 20 THEN CEIL((ce.valuenum - 20) / 5.0)
                    ELSE 0
                END
            -- Temperature C (itemid: 223762). Normal: 36.1-37.2 C. +1 point per 0.5 C deviation.
            WHEN 223762 THEN
                CASE
                    WHEN ce.valuenum < 36.1 THEN CEIL((36.1 - ce.valuenum) / 0.5)
                    WHEN ce.valuenum > 37.2 THEN CEIL((ce.valuenum - 37.2) / 0.5)
                    ELSE 0
                END
            -- SpO2 (itemid: 220277). Normal: 90-100%. +1 point per 5% below 90%.
            WHEN 220277 THEN
                CASE
                    WHEN ce.valuenum < 90 THEN CEIL((90 - ce.valuenum) / 5.0)
                    ELSE 0
                END
            ELSE 0 -- Should not be reached given the WHERE clause on itemid
        END AS instability_points
    FROM
        cohort_filtered c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (220045, 220179, 220210, 223762, 220277)
        AND ce.valuenum IS NOT NULL -- Exclude non-numeric values
        AND ce.valuenum >= 0     -- Exclude potentially erroneous negative values
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
),
final_instability_scores AS (
    -- Aggregate instability points per ICU stay
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        c.los,
        c.hospital_expire_flag,
        COALESCE(SUM(rs.instability_points), 0) AS total_instability_score -- Sum points; 0 if no relevant vital signs recorded
    FROM
        cohort_filtered c
    LEFT JOIN
        raw_vital_scores rs ON c.stay_id = rs.stay_id
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id, c.los, c.hospital_expire_flag
),
ranked_cohort AS (
    -- Step 3 & 4: Calculate percentile ranks and identify quartiles
    SELECT
        *,
        PERCENT_RANK() OVER (ORDER BY total_instability_score ASC) AS percentile_rank,
        NTILE(4) OVER (ORDER BY total_instability_score DESC) AS instability_quartile
    FROM
        final_instability_scores
)
-- Final Output:
SELECT
    -- Part 1: Percentile of a given score (80)
    (SELECT MAX(percentile_rank) FROM ranked_cohort WHERE total_instability_score <= 80) AS percentile_of_score_80,

    -- Part 2: ICU LOS and mortality for the top instability quartile
    AVG(CASE WHEN instability_quartile = 1 THEN los END) AS avg_los_top_quartile,
    (SUM(CASE WHEN instability_quartile = 1 THEN hospital_expire_flag ELSE 0 END) * 100.0) / COUNT(CASE WHEN instability_quartile = 1 THEN stay_id END) AS mortality_rate_top_quartile
FROM
    ranked_cohort;