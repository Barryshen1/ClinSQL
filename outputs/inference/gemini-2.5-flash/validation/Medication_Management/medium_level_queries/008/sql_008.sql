WITH admission_cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND adm.dischtime IS NOT NULL -- Ensure dischtime is available for last 48h calculation
        AND EXISTS ( -- Patient has Type 2 Diabetes Mellitus
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_t2dm
            WHERE diag_t2dm.subject_id = adm.subject_id
              AND diag_t2dm.hadm_id = adm.hadm_id
              AND (
                      (diag_t2dm.icd_version = 9 AND diag_t2dm.icd_code LIKE '250.%')
                      OR (diag_t2dm.icd_version = 10 AND diag_t2dm.icd_code LIKE 'E11.%')
                  )
        )
        AND EXISTS ( -- Patient has Heart Failure
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
            WHERE diag_hf.subject_id = adm.subject_id
              AND diag_hf.hadm_id = adm.hadm_id
              AND (
                      (diag_hf.icd_version = 9 AND diag_hf.icd_code LIKE '428.%')
                      OR (diag_hf.icd_version = 10 AND diag_hf.icd_code LIKE 'I50.%')
                  )
        )
),
med_events AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        -- Define medication types
        CASE WHEN LOWER(p.drug) LIKE '%insulin%' THEN TRUE ELSE FALSE END AS is_insulin,
        CASE WHEN LOWER(p.drug) LIKE '%metformin%'
                  OR LOWER(p.drug) LIKE '%glipizide%'
                  OR LOWER(p.drug) LIKE '%glyburide%'
                  OR LOWER(p.drug) LIKE '%glimepiride%'
                  OR LOWER(p.drug) LIKE '%sitagliptin%'
                  OR LOWER(p.drug) LIKE '%saxagliptin%'
                  OR LOWER(p.drug) LIKE '%linagliptin%'
                  OR LOWER(p.drug) LIKE '%alogliptin%'
                  OR LOWER(p.drug) LIKE '%empagliflozin%' -- SGLT2
                  OR LOWER(p.drug) LIKE '%dapagliflozin%' -- SGLT2
                  OR LOWER(p.drug) LIKE '%canagliflozin%' -- SGLT2
                  OR LOWER(p.drug) LIKE '%pioglitazone%' -- TZD
                  OR LOWER(p.drug) LIKE '%rosiglitazone%' -- TZD
                  OR LOWER(p.drug) LIKE '%repaglinide%' -- Meglitinide
                  OR LOWER(p.drug) LIKE '%nateglinide%' -- Meglitinide
                  OR LOWER(p.drug) LIKE '%acarbose%' -- Alpha-glucosidase inhibitor
                  OR LOWER(p.drug) LIKE '%miglitol%' -- Alpha-glucosidase inhibitor
             THEN TRUE ELSE FALSE END AS is_oral_agent,
        -- Define time windows and check prescription starttime relevance
        p.starttime >= ac.admittime AND p.starttime < DATETIME_ADD(ac.admittime, INTERVAL 24 HOUR) AS in_first_24h,
        p.starttime >= GREATEST(ac.admittime, DATETIME_SUB(ac.dischtime, INTERVAL 48 HOUR)) AND p.starttime < ac.dischtime AS in_last_48h
    FROM admission_cohort ac
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
        ON ac.subject_id = p.subject_id AND ac.hadm_id = p.hadm_id
    WHERE
        -- Optimize by only considering relevant drugs in the join
        LOWER(p.drug) LIKE '%insulin%'
        OR LOWER(p.drug) LIKE '%metformin%'
        OR LOWER(p.drug) LIKE '%glipizide%'
        OR LOWER(p.drug) LIKE '%glyburide%'
        OR LOWER(p.drug) LIKE '%glimepiride%'
        OR LOWER(p.drug) LIKE '%sitagliptin%'
        OR LOWER(p.drug) LIKE '%saxagliptin%'
        OR LOWER(p.drug) LIKE '%linagliptin%'
        OR LOWER(p.drug) LIKE '%alogliptin%'
        OR LOWER(p.drug) LIKE '%empagliflozin%'
        OR LOWER(p.drug) LIKE '%dapagliflozin%'
        OR LOWER(p.drug) LIKE '%canagliflozin%'
        OR LOWER(p.drug) LIKE '%pioglitazone%'
        OR LOWER(p.drug) LIKE '%rosiglitazone%'
        OR LOWER(p.drug) LIKE '%repaglinide%'
        OR LOWER(p.drug) LIKE '%nateglinide%'
        OR LOWER(p.drug) LIKE '%acarbose%'
        OR LOWER(p.drug) LIKE '%miglitol%'
),
patient_med_summary AS (
    SELECT
        subject_id,
        hadm_id,
        MAX(CASE WHEN is_insulin AND in_first_24h THEN 1 ELSE 0 END) AS has_insulin_first_24h,
        MAX(CASE WHEN is_oral_agent AND in_first_24h THEN 1 ELSE 0 END) AS has_oral_first_24h,
        MAX(CASE WHEN is_insulin AND in_last_48h THEN 1 ELSE 0 END) AS has_insulin_last_48h,
        MAX(CASE WHEN is_oral_agent AND in_last_48h THEN 1 ELSE 0 END) AS has_oral_last_48h
    FROM med_events
    GROUP BY subject_id, hadm_id
)
SELECT
    COUNT(DISTINCT pms.hadm_id) AS total_admissions_with_med_data,

    -- Insulin statistics for first 24h
    SUM(pms.has_insulin_first_24h) AS insulin_first_24h_count,
    ROUND(SUM(pms.has_insulin_first_24h) * 100.0 / COUNT(pms.hadm_id), 2) AS insulin_first_24h_prevalence_pct,

    -- Insulin statistics for last 48h
    SUM(pms.has_insulin_last_48h) AS insulin_last_48h_count,
    ROUND(SUM(pms.has_insulin_last_48h) * 100.0 / COUNT(pms.hadm_id), 2) AS insulin_last_48h_prevalence_pct,

    -- Insulin change counts
    SUM(CASE WHEN pms.has_insulin_first_24h = 0 AND pms.has_insulin_last_48h = 1 THEN 1 ELSE 0 END) AS insulin_initiated_count,
    SUM(CASE WHEN pms.has_insulin_first_24h = 1 AND pms.has_insulin_last_48h = 1 THEN 1 ELSE 0 END) AS insulin_continued_count,
    SUM(CASE WHEN pms.has_insulin_first_24h = 1 AND pms.has_insulin_last_48h = 0 THEN 1 ELSE 0 END) AS insulin_discontinued_count,

    -- Oral Agent statistics for first 24h
    SUM(pms.has_oral_first_24h) AS oral_first_24h_count,
    ROUND(SUM(pms.has_oral_first_24h) * 100.0 / COUNT(pms.hadm_id), 2) AS oral_first_24h_prevalence_pct,

    -- Oral Agent statistics for last 48h
    SUM(pms.has_oral_last_48h) AS oral_last_48h_count,
    ROUND(SUM(pms.has_oral_last_48h) * 100.0 / COUNT(pms.hadm_id), 2) AS oral_last_48h_prevalence_pct,

    -- Oral Agent change counts
    SUM(CASE WHEN pms.has_oral_first_24h = 0 AND pms.has_oral_last_48h = 1 THEN 1 ELSE 0 END) AS oral_initiated_count,
    SUM(CASE WHEN pms.has_oral_first_24h = 1 AND pms.has_oral_last_48h = 1 THEN 1 ELSE 0 END) AS oral_continued_count,
    SUM(CASE WHEN pms.has_oral_first_24h = 1 AND pms.has_oral_last_48h = 0 THEN 1 ELSE 0 END) AS oral_discontinued_count
FROM patient_med_summary pms;