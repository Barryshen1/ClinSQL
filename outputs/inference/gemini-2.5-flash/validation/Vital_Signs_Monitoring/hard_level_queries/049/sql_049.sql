WITH sepsis_patients AS (
    -- Step 1: Identify the main cohort of male ICU patients aged 78-88 with sepsis.
    -- Sepsis is identified using common ICD-9 and ICD-10 codes.
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.hadm_id = icu.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 78 AND 88
        AND (
            -- ICD-9 codes for Sepsis, Severe Sepsis
            (di.icd_version = 9 AND di.icd_code IN ('99591', '99592', '78552'))
            OR
            -- ICD-10 codes for Sepsis, other bacterial sepsis
            (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%'))
        )
),
instability_scores AS (
    -- Step 2: Calculate the "instability score" for each ICU stay in the sepsis cohort.
    -- The instability score is defined as the count of individual lab measurements that are
    -- outside their reference range within the first 24 hours of the ICU stay.
    SELECT
        sp.subject_id,
        sp.hadm_id,
        sp.stay_id,
        sp.los,
        sp.hospital_expire_flag,
        -- Count only lab events that are outside the normal reference range
        -- LEFT JOIN ensures all patients from sepsis_patients are included, even those with 0 abnormal labs
        COUNT(le.labevent_id) AS instability_score
    FROM
        sepsis_patients sp
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sp.subject_id = le.subject_id
        AND sp.hadm_id = le.hadm_id
        -- Filter lab events to the first 24 hours of ICU stay
        AND le.charttime BETWEEN sp.intime AND DATETIME_ADD(sp.intime, INTERVAL 24 HOUR)
        -- Ensure valid numerical value and reference ranges exist
        AND le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        -- Identify abnormal values (valuenum outside lower and upper reference range)
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    GROUP BY
        sp.subject_id, sp.hadm_id, sp.stay_id, sp.los, sp.hospital_expire_flag
),
ranked_cohort AS (
    -- Step 3 & 4: Rank instability scores and assign quartiles for further analysis.
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        hospital_expire_flag,
        instability_score,
        -- Assign quartile (1-4 range) based on instability score
        NTILE(4) OVER (ORDER BY instability_score ASC) AS instability_quartile
    FROM
        instability_scores
)
-- Final SELECT: Retrieve the requested percentile rank and quartile statistics.
SELECT
    -- Calculate the percentile rank of an instability score of 85.
    -- This is defined as the percentage of patients whose instability score is less than or equal to 85.
    CAST(SUM(CASE WHEN rc.instability_score <= 85 THEN 1 ELSE 0 END) AS FLOAT64) * 100.0 / COUNT(rc.instability_score) AS percentile_rank_score_85,
    -- Calculate the mean ICU Length of Stay (LOS) for patients in the 4th (highest) instability quartile.
    AVG(CASE WHEN rc.instability_quartile = 4 THEN rc.los END) AS mean_icu_los_quartile4,
    -- Calculate the hospital mortality rate for patients in the 4th instability quartile.
    -- Hospital_expire_flag = 1 for death, 0 for survival. Average gives the proportion (rate).
    AVG(CASE WHEN rc.instability_quartile = 4 THEN rc.hospital_expire_flag END) AS hospital_mortality_quartile4
FROM
    ranked_cohort rc;