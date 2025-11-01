WITH t2dm_admissions AS (
    -- Identify admissions with Type 2 Diabetes Mellitus (T2DM) diagnoses
    SELECT DISTINCT
        dicd.subject_id,
        dicd.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
    WHERE
        dicd.icd_version IN (9, 10)
        AND (
               -- Type 2 Diabetes Mellitus (T2DM) ICD-9 codes
               (dicd.icd_version = 9 AND dicd.icd_code LIKE '250.%')
            OR
               -- Type 2 Diabetes Mellitus (T2DM) ICD-10 codes
               (dicd.icd_version = 10 AND dicd.icd_code LIKE 'E11%')
        )
),
hf_admissions AS (
    -- Identify admissions with Heart Failure (HF) diagnoses
    SELECT DISTINCT
        dicd.subject_id,
        dicd.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
    WHERE
        dicd.icd_version IN (9, 10)
        AND (
               -- Heart Failure (HF) ICD-9 codes
               (dicd.icd_version = 9 AND dicd.icd_code LIKE '428.%')
            OR
               -- Heart Failure (HF) ICD-10 codes
               (dicd.icd_version = 10 AND dicd.icd_code LIKE 'I50%')
        )
),
cohort AS (
    -- Select female patients aged 83-93 with both T2DM and Heart Failure diagnoses
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.patients pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        t2dm_admissions t2dm -- Join to check for T2DM diagnosis
        ON ad.subject_id = t2dm.subject_id AND ad.hadm_id = t2dm.hadm_id
    INNER JOIN
        hf_admissions hf -- Join to check for HF diagnosis
        ON ad.subject_id = hf.subject_id AND ad.hadm_id = hf.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 83 AND 93
),
first_insulin_prescriptions AS (
    -- Find the earliest prescription time for each insulin type for each patient in the cohort
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        MIN(CASE WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' OR LOWER(p.drug) LIKE '%nph insulin%' THEN p.starttime END) AS first_basal_insulin_time,
        MIN(CASE WHEN LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%glulisine%' OR (LOWER(p.drug) LIKE '%insulin%' AND LOWER(p.drug) LIKE '%regular%') THEN p.starttime END) AS first_bolus_insulin_time,
        MIN(CASE WHEN LOWER(p.drug) LIKE '%sliding scale insulin%' OR LOWER(p.drug) LIKE '%ssi%' THEN p.starttime END) AS first_ssi_insulin_time
    FROM
        cohort c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.prescriptions p
        ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
    WHERE
        LOWER(p.drug) LIKE '%insulin%' -- Filter for any insulin prescription to reduce rows
    GROUP BY
        c.subject_id, c.hadm_id, c.admittime, c.dischtime
),
insulin_initiation_flags AS (
    -- Flag patients who initiated each insulin type within the specified time windows
    SELECT
        fip.subject_id,
        fip.hadm_id,
        -- First 48 hours from admission
        CASE WHEN fip.first_basal_insulin_time IS NOT NULL AND fip.first_basal_insulin_time <= DATETIME_ADD(fip.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS basal_48h,
        CASE WHEN fip.first_bolus_insulin_time IS NOT NULL AND fip.first_bolus_insulin_time <= DATETIME_ADD(fip.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS bolus_48h,
        CASE WHEN fip.first_ssi_insulin_time IS NOT NULL AND fip.first_ssi_insulin_time <= DATETIME_ADD(fip.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS ssi_48h,
        -- Basal-bolus strategy: both basal and bolus initiated within first 48h
        CASE WHEN (fip.first_basal_insulin_time IS NOT NULL AND fip.first_basal_insulin_time <= DATETIME_ADD(fip.admittime, INTERVAL 48 HOUR))
                  AND (fip.first_bolus_insulin_time IS NOT NULL AND fip.first_bolus_insulin_time <= DATETIME_ADD(fip.admittime, INTERVAL 48 HOUR))
             THEN 1 ELSE 0 END AS basal_bolus_48h,

        -- Final 12 hours before discharge (only if dischtime is not NULL)
        CASE WHEN fip.dischtime IS NOT NULL
                  AND fip.first_basal_insulin_time IS NOT NULL
                  AND fip.first_basal_insulin_time >= DATETIME_SUB(fip.dischtime, INTERVAL 12 HOUR)
                  AND fip.first_basal_insulin_time <= fip.dischtime THEN 1 ELSE 0 END AS basal_12h,
        CASE WHEN fip.dischtime IS NOT NULL
                  AND fip.first_bolus_insulin_time IS NOT NULL
                  AND fip.first_bolus_insulin_time >= DATETIME_SUB(fip.dischtime, INTERVAL 12 HOUR)
                  AND fip.first_bolus_insulin_time <= fip.dischtime THEN 1 ELSE 0 END AS bolus_12h,
        CASE WHEN fip.dischtime IS NOT NULL
                  AND fip.first_ssi_insulin_time IS NOT NULL
                  AND fip.first_ssi_insulin_time >= DATETIME_SUB(fip.dischtime, INTERVAL 12 HOUR)
                  AND fip.first_ssi_insulin_time <= fip.dischtime THEN 1 ELSE 0 END AS ssi_12h,
        -- Basal-bolus strategy: both basal and bolus initiated within final 12h
        CASE WHEN fip.dischtime IS NOT NULL
                  AND (fip.first_basal_insulin_time IS NOT NULL AND fip.first_basal_insulin_time >= DATETIME_SUB(fip.dischtime, INTERVAL 12 HOUR) AND fip.first_basal_insulin_time <= fip.dischtime)
                  AND (fip.first_bolus_insulin_time IS NOT NULL AND fip.first_bolus_insulin_time >= DATETIME_SUB(fip.dischtime, INTERVAL 12 HOUR) AND fip.first_bolus_insulin_time <= fip.dischtime)
             THEN 1 ELSE 0 END AS basal_bolus_12h
    FROM
        first_insulin_prescriptions fip
)
SELECT
    -- Total count of unique admissions in the cohort
    COUNT(DISTINCT iif.hadm_id) AS total_cohort_admissions,

    -- Counts of initiation within the first 48 hours
    SUM(iif.basal_48h) AS count_basal_first_48h,
    SUM(iif.bolus_48h) AS count_bolus_first_48h,
    SUM(iif.basal_bolus_48h) AS count_basal_bolus_first_48h,
    SUM(iif.ssi_48h) AS count_ssi_first_48h,

    -- Percentages of initiation within the first 48 hours
    SAFE_DIVIDE(SUM(iif.basal_48h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_basal_first_48h,
    SAFE_DIVIDE(SUM(iif.bolus_48h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_bolus_first_48h,
    SAFE_DIVIDE(SUM(iif.basal_bolus_48h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_basal_bolus_first_48h,
    SAFE_DIVIDE(SUM(iif.ssi_48h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_ssi_first_48h,

    -- Counts of initiation within the final 12 hours
    SUM(iif.basal_12h) AS count_basal_final_12h,
    SUM(iif.bolus_12h) AS count_bolus_final_12h,
    SUM(iif.basal_bolus_12h) AS count_basal_bolus_final_12h,
    SUM(iif.ssi_12h) AS count_ssi_final_12h,

    -- Percentages of initiation within the final 12 hours
    SAFE_DIVIDE(SUM(iif.basal_12h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_basal_final_12h,
    SAFE_DIVIDE(SUM(iif.bolus_12h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_bolus_final_12h,
    SAFE_DIVIDE(SUM(iif.basal_bolus_12h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_basal_bolus_final_12h,
    SAFE_DIVIDE(SUM(iif.ssi_12h), COUNT(DISTINCT iif.hadm_id)) * 100 AS pct_ssi_final_12h,

    -- Net change (Percentage in First 48h - Percentage in Final 12h)
    (SAFE_DIVIDE(SUM(iif.basal_48h), COUNT(DISTINCT iif.hadm_id)) * 100) - (SAFE_DIVIDE(SUM(iif.basal_12h), COUNT(DISTINCT iif.hadm_id)) * 100) AS net_change_basal,
    (SAFE_DIVIDE(SUM(iif.bolus_48h), COUNT(DISTINCT iif.hadm_id)) * 100) - (SAFE_DIVIDE(SUM(iif.bolus_12h), COUNT(DISTINCT iif.hadm_id)) * 100) AS net_change_bolus,
    (SAFE_DIVIDE(SUM(iif.basal_bolus_48h), COUNT(DISTINCT iif.hadm_id)) * 100) - (SAFE_DIVIDE(SUM(iif.basal_bolus_12h), COUNT(DISTINCT iif.hadm_id)) * 100) AS net_change_basal_bolus,
    (SAFE_DIVIDE(SUM(iif.ssi_48h), COUNT(DISTINCT iif.hadm_id)) * 100) - (SAFE_DIVIDE(SUM(iif.ssi_12h), COUNT(DISTINCT iif.hadm_id)) * 100) AS net_change_ssi
FROM
    insulin_initiation_flags iif;