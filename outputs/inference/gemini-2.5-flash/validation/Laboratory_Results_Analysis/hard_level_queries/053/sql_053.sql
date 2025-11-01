WITH
-- Step 1: Define the target patient cohort (Male, 68-78, Lower GI Bleeding)
CohortPatients AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 68 AND 78
        AND (
            -- ICD-10 codes for Melena (K92.1) and GI hemorrhage, unspecified (K92.2)
            (di.icd_version = 10 AND di.icd_code IN ('K921', 'K922'))
            OR
            -- ICD-9 codes for Melena (578.1) and GI hemorrhage, unspecified (578.9)
            (di.icd_version = 9 AND di.icd_code IN ('5781', '5789'))
        )
    GROUP BY -- Deduplicate admissions if they have multiple relevant diagnoses
        ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.hospital_expire_flag, los_days
),
-- Step 2.1: Calculate 72-hour lab instability score (raw, only for abnormal labs)
LabInstabilityScoresRaw AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        COUNT(DISTINCT le.itemid) AS instability_score
    FROM
        CohortPatients AS cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN cp.admittime AND DATETIME_ADD(cp.admittime, INTERVAL 72 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        cp.subject_id, cp.hadm_id
),
-- Step 2.2: Include all cohort patients, assigning 0 score if no abnormal labs in 72h
LabInstabilityScores AS (
    SELECT
        cp.subject_id,
        cp.hadm_id,
        COALESCE(lis_raw.instability_score, 0) AS instability_score,
        cp.admittime,
        cp.dischtime,
        cp.hospital_expire_flag,
        cp.los_days
    FROM
        CohortPatients AS cp
    LEFT JOIN
        LabInstabilityScoresRaw AS lis_raw
        ON cp.subject_id = lis_raw.subject_id AND cp.hadm_id = lis_raw.hadm_id
),
-- Step 3: Calculate the 90th percentile of this score
PercentileThreshold AS (
    SELECT
        PERCENTILE_CONT(instability_score, 0.9) OVER() AS percentile_90_score
    FROM
        LabInstabilityScores
    LIMIT 1 -- PERCENTILE_CONT without PARTITION BY returns a single value
),
-- Step 4: Identify "top-tier patients" (score >= 90th percentile)
TopTierPatients AS (
    SELECT
        lis.subject_id,
        lis.hadm_id,
        lis.admittime,
        lis.dischtime,
        lis.hospital_expire_flag,
        lis.los_days,
        lis.instability_score
    FROM
        LabInstabilityScores AS lis,
        PercentileThreshold AS pt
    WHERE
        lis.instability_score >= pt.percentile_90_score
),
-- Step 5: Identify specific lab itemids and their precise labels
SpecificLabItemIDs AS (
    SELECT itemid, label
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
        itemid IN (
            50912, -- Creatinine
            50970, -- Potassium (Serum)
            52655, -- Potassium, Whole Blood
            51265, -- Platelets
            50908, -- Hemoglobin
            51300  -- WBC
        )
),
-- Step 6: Get all relevant lab abnormalities for specific labs for the entire admission
AllLabAbnormalities AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        MAX(CASE WHEN sli.label = 'Creatinine' THEN 1 ELSE 0 END) AS had_abnormal_Cr,
        MAX(CASE WHEN sli.label = 'Potassium' THEN 1 ELSE 0 END) AS had_abnormal_K, -- Serum Potassium
        MAX(CASE WHEN sli.label = 'Potassium, Whole Blood' THEN 1 ELSE 0 END) AS had_abnormal_WholeBloodK,
        MAX(CASE WHEN sli.label = 'Platelets' THEN 1 ELSE 0 END) AS had_abnormal_Platelets,
        MAX(CASE WHEN sli.label = 'Hemoglobin' THEN 1 ELSE 0 END) AS had_abnormal_Hgb,
        MAX(CASE WHEN sli.label = 'WBC' THEN 1 ELSE 0 END) AS had_abnormal_WBC
    FROM
        CohortPatients AS cp
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cp.subject_id = le.subject_id AND cp.hadm_id = le.hadm_id
    INNER JOIN
        SpecificLabItemIDs AS sli
        ON le.itemid = sli.itemid
    WHERE
        le.flag = 'abnormal' -- Only considering abnormal flags for critical rates
    GROUP BY
        le.subject_id, le.hadm_id
)
-- Final Output: Combine all requested metrics
SELECT
    -- Part 1: 90th-percentile 72-h lab-instability score
    (SELECT percentile_90_score FROM PercentileThreshold) AS percentile_90th_72h_lab_instability_score,

    -- Part 2: Metrics for "top-tier patients"
    (SELECT COUNT(DISTINCT hadm_id) FROM TopTierPatients) AS top_tier_admissions_count,
    (SELECT AVG(CAST(hospital_expire_flag AS BIGNUMERIC)) FROM TopTierPatients) AS top_tier_mortality_rate,
    (SELECT AVG(los_days) FROM TopTierPatients) AS top_tier_avg_los_days,

    -- Critical rates for specific labs for top-tier patients
    (SELECT AVG(COALESCE(ala.had_abnormal_Cr, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_Cr,
    (SELECT AVG(COALESCE(ala.had_abnormal_K, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_Potassium,
    (SELECT AVG(COALESCE(ala.had_abnormal_Platelets, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_Platelets,
    (SELECT AVG(COALESCE(ala.had_abnormal_Hgb, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_Hemoglobin,
    (SELECT AVG(COALESCE(ala.had_abnormal_WholeBloodK, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_WholeBloodK,
    (SELECT AVG(COALESCE(ala.had_abnormal_WBC, 0)) FROM TopTierPatients ttp LEFT JOIN AllLabAbnormalities ala ON ttp.subject_id = ala.subject_id AND ttp.hadm_id = ala.hadm_id) AS top_tier_critical_rate_WBC,

    -- Part 3: Comparison of critical rates versus all inpatients (i.e., the initial cohort)
    (SELECT COUNT(DISTINCT hadm_id) FROM CohortPatients) AS cohort_admissions_count,
    (SELECT AVG(CAST(hospital_expire_flag AS BIGNUMERIC)) FROM CohortPatients) AS cohort_mortality_rate,
    (SELECT AVG(los_days) FROM CohortPatients) AS cohort_avg_los_days,
    (SELECT AVG(COALESCE(ala.had_abnormal_Cr, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_Cr,
    (SELECT AVG(COALESCE(ala.had_abnormal_K, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_Potassium,
    (SELECT AVG(COALESCE(ala.had_abnormal_Platelets, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_Platelets,
    (SELECT AVG(COALESCE(ala.had_abnormal_Hgb, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_Hemoglobin,
    (SELECT AVG(COALESCE(ala.had_abnormal_WholeBloodK, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_WholeBloodK,
    (SELECT AVG(COALESCE(ala.had_abnormal_WBC, 0)) FROM CohortPatients cp LEFT JOIN AllLabAbnormalities ala ON cp.subject_id = ala.subject_id AND cp.hadm_id = ala.hadm_id) AS cohort_critical_rate_WBC;