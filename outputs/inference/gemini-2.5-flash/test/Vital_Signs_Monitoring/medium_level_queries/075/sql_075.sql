WITH cohort_map_data AS (
    -- Select male ICU patients aged 56-66 and calculate their average MAP per ICU stay
    SELECT
        p.subject_id,
        icustays.hadm_id, -- Corrected: hadm_id comes from icustays, not patients
        icustays.stay_id,
        AVG(ce.valuenum) AS avg_map
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icustays
        ON p.subject_id = icustays.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icustays.stay_id = ce.stay_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 56 AND 66
        -- Itemids for Mean Arterial Pressure (Arterial BP Mean, Non-invasive BP Mean)
        AND ce.itemid IN (220050, 220181) 
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
    GROUP BY
        p.subject_id, icustays.hadm_id, icustays.stay_id
),
stroke_status AS (
    -- Determine if an admission (hadm_id) had a stroke diagnosis
    SELECT
        diag.hadm_id,
        MAX(CASE
            WHEN (diag.icd_version = 9 AND diag.icd_code BETWEEN '430' AND '43899') THEN 1 -- ICD9: 430-438 for Cerebrovascular disease (using BETWEEN for more precision than LIKE '43%')
            WHEN (diag.icd_version = 10 AND diag.icd_code BETWEEN 'I60' AND 'I699') THEN 1 -- ICD10: I60-I69 for Cerebrovascular diseases (using BETWEEN for more precision than LIKE 'I6%')
            ELSE 0
        END) AS hadm_has_stroke_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    GROUP BY
        diag.hadm_id
)
-- Combine MAP data with stroke status, categorize MAP, and then aggregate results
SELECT
    map_category,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    COUNT(DISTINCT CASE WHEN hadm_has_stroke_flag = 1 THEN hadm_id END) AS admissions_with_stroke,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN hadm_has_stroke_flag = 1 THEN hadm_id END), COUNT(DISTINCT hadm_id)) AS stroke_rate_per_admission
FROM (
    -- Subquery to classify each ICU stay by MAP category and stroke status
    SELECT
        cmd.subject_id,
        cmd.hadm_id,
        cmd.stay_id, -- Keep stay_id for understanding granularity, although not directly aggregated on
        cmd.avg_map,
        COALESCE(ss.hadm_has_stroke_flag, 0) AS hadm_has_stroke_flag,
        CASE
            WHEN cmd.avg_map < 65 THEN '<65 mmHg'
            WHEN cmd.avg_map BETWEEN 65 AND 74 THEN '65-74 mmHg'
            WHEN cmd.avg_map BETWEEN 75 AND 84 THEN '75-84 mmHg'
            WHEN cmd.avg_map >= 85 THEN '>=85 mmHg'
            ELSE 'Unknown Category' -- Should not be reached if avg_map is always > 0
        END AS map_category
    FROM
        cohort_map_data cmd
    LEFT JOIN
        stroke_status ss
        ON cmd.hadm_id = ss.hadm_id
) AS classified_stays
GROUP BY
    map_category
ORDER BY
    CASE map_category
        WHEN '<65 mmHg' THEN 1
        WHEN '65-74 mmHg' THEN 2
        WHEN '75-84 mmHg' THEN 3
        WHEN '>=85 mmHg' THEN 4
        ELSE 99 -- For any unexpected 'Unknown Category'
    END;