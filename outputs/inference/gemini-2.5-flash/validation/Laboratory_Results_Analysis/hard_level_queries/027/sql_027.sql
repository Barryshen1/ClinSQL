WITH cohort_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 89 AND 99
        -- Ensure the admission has a lower GI bleed diagnosis (ICD-10 codes)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.icd_version = 10 -- Focusing on ICD-10
                AND di.icd_code IN (
                    'K625', -- Hemorrhage of anus and rectum (explicitly lower GI)
                    'K921'  -- Melena (strongly indicative of GI bleed, often lower)
                )
        )
),
-- Step 2: Identify specific critical lab itemids
critical_lab_itemids AS (
    SELECT
        itemid,
        label
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        itemid IN (
            50811, -- Hemoglobin
            51265, -- Platelet Count
            50912, -- Creatinine
            50983, -- Sodium
            50971, -- Potassium
            51300  -- WBC (White Blood Cell Count)
        )
),
-- Step 3: Calculate the 72-hour lab instability score (raw count of distinct abnormal critical labs)
lab_instability_score_raw AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM
        cohort_admissions ca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ca.subject_id = le.subject_id
        AND ca.hadm_id = le.hadm_id
    INNER JOIN
        critical_lab_itemids cli
        ON le.itemid = cli.itemid
    WHERE
        -- Lab event occurred within the first 72 hours of admission
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 72 HOUR)
        -- Lab value is not NULL and is outside the reference range (abnormal)
        AND le.valuenum IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
    GROUP BY
        ca.subject_id,
        ca.hadm_id
),
-- Step 4: Include admissions with 0 abnormal critical labs (by linking back to cohort_admissions)
lab_instability_score AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        ca.hospital_expire_flag,
        COALESCE(lisr.instability_score, 0) AS instability_score -- Assign 0 if no abnormal labs found
    FROM
        cohort_admissions ca
    LEFT JOIN
        lab_instability_score_raw lisr
        ON ca.subject_id = lisr.subject_id
        AND ca.hadm_id = lisr.hadm_id
),
-- Step 5: Stratify into quintiles and calculate LOS
cohort_with_quintiles AS (
    SELECT
        subject_id,
        hadm_id,
        instability_score,
        DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days, -- Calculate LOS in days
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY instability_score ASC, hadm_id ASC) AS instability_quintile -- Stratify into 5 quintiles
    FROM
        lab_instability_score
)
-- Step 6: Report outcomes per quintile and general inpatient rate
SELECT
    instability_quintile,
    -- Outcomes for each quintile
    ROUND(AVG(t.los_days), 2) AS avg_los_days,
    ROUND(AVG(t.hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
    ROUND(AVG(t.instability_score), 2) AS quintile_critical_lab_score_avg, -- Changed name for clarity. This is the avg score for the quintile.
    -- Overall cohort average for comparison
    ROUND((SELECT AVG(instability_score) FROM cohort_with_quintiles), 2) AS general_cohort_critical_lab_score_avg
FROM
    cohort_with_quintiles t
GROUP BY
    instability_quintile
ORDER BY
    instability_quintile;