WITH cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_dm
        ON adm.hadm_id = diag_dm.hadm_id
        AND diag_dm.icd_code LIKE 'E11%'
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
        ON adm.hadm_id = diag_hf.hadm_id
        AND diag_hf.icd_code LIKE 'I50%'
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 45 AND 55
),

insulin_first_12h AS (
    SELECT
        cohort.hadm_id,
        1 AS insulin_initiated
    FROM cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
        ON cohort.hadm_id = rx.hadm_id
    WHERE
        rx.starttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 12 HOUR)
        AND LOWER(rx.drug) LIKE '%insulin%'
    GROUP BY cohort.hadm_id
),

insulin_final_72h AS (
    SELECT
        cohort.hadm_id,
        1 AS insulin_initiated
    FROM cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
        ON cohort.hadm_id = rx.hadm_id
    WHERE
        rx.starttime BETWEEN DATETIME_SUB(cohort.dischtime, INTERVAL 72 HOUR) AND cohort.dischtime
        AND LOWER(rx.drug) LIKE '%insulin%'
    GROUP BY cohort.hadm_id
),

oral_first_12h AS (
    SELECT
        cohort.hadm_id,
        1 AS oral_initiated
    FROM cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
        ON cohort.hadm_id = rx.hadm_id
    WHERE
        rx.starttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 12 HOUR)
        AND (
            LOWER(rx.drug) LIKE '%metformin%'
            OR LOWER(rx.drug) LIKE '%glipizide%'
            OR LOWER(rx.drug) LIKE '%glyburide%'
            OR LOWER(rx.drug) LIKE '%sitagliptin%'
            OR LOWER(rx.drug) LIKE '%pioglitazone%'
            OR LOWER(rx.drug) LIKE '%empagliflozin%'
            OR LOWER(rx.drug) LIKE '%dapagliflozin%'
            OR LOWER(rx.drug) LIKE '%linagliptin%'
            OR LOWER(rx.drug) LIKE '%saxagliptin%'
            OR LOWER(rx.drug) LIKE '%canagliflozin%'
        )
    GROUP BY cohort.hadm_id
),

oral_final_72h AS (
    SELECT
        cohort.hadm_id,
        1 AS oral_initiated
    FROM cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
        ON cohort.hadm_id = rx.hadm_id
    WHERE
        rx.starttime BETWEEN DATETIME_SUB(cohort.dischtime, INTERVAL 72 HOUR) AND cohort.dischtime
        AND (
            LOWER(rx.drug) LIKE '%metformin%'
            OR LOWER(rx.drug) LIKE '%glipizide%'
            OR LOWER(rx.drug) LIKE '%glyburide%'
            OR LOWER(rx.drug) LIKE '%sitagliptin%'
            OR LOWER(rx.drug) LIKE '%pioglitazone%'
            OR LOWER(rx.drug) LIKE '%empagliflozin%'
            OR LOWER(rx.drug) LIKE '%dapagliflozin%'
            OR LOWER(rx.drug) LIKE '%linagliptin%'
            OR LOWER(rx.drug) LIKE '%saxagliptin%'
            OR LOWER(rx.drug) LIKE '%canagliflozin%'
        )
    GROUP BY cohort.hadm_id
)

SELECT
    'Insulin' AS medication_type,
    COUNT(DISTINCT cohort.hadm_id) AS total_admissions,
    COUNT(DISTINCT insulin_first_12h.hadm_id) AS init_first_12h,
    ROUND(100 * COUNT(DISTINCT insulin_first_12h.hadm_id) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_first_12h,
    COUNT(DISTINCT insulin_final_72h.hadm_id) AS init_final_72h,
    ROUND(100 * COUNT(DISTINCT insulin_final_72h.hadm_id) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_final_72h,
    ROUND(
        100 * COUNT(DISTINCT insulin_first_12h.hadm_id) / COUNT(DISTINCT cohort.hadm_id) -
        100 * COUNT(DISTINCT insulin_final_72h.hadm_id) / COUNT(DISTINCT cohort.hadm_id),
        2
    ) AS pp_difference
FROM cohort
LEFT JOIN insulin_first_12h ON cohort.hadm_id = insulin_first_12h.hadm_id
LEFT JOIN insulin_final_72h ON cohort.hadm_id = insulin_final_72h.hadm_id

UNION ALL

SELECT
    'Oral antidiabetics' AS medication_type,
    COUNT(DISTINCT cohort.hadm_id) AS total_admissions,
    COUNT(DISTINCT oral_first_12h.hadm_id) AS init_first_12h,
    ROUND(100 * COUNT(DISTINCT oral_first_12h.hadm_id) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_first_12h,
    COUNT(DISTINCT oral_final_72h.hadm_id) AS init_final_72h,
    ROUND(100 * COUNT(DISTINCT oral_final_72h.hadm_id) / COUNT(DISTINCT cohort.hadm_id), 2) AS pct_final_72h,
    ROUND(
        100 * COUNT(DISTINCT oral_first_12h.hadm_id) / COUNT(DISTINCT cohort.hadm_id) -
        100 * COUNT(DISTINCT oral_final_72h.hadm_id) / COUNT(DISTINCT cohort.hadm_id),
        2
    ) AS pp_difference
FROM cohort
LEFT JOIN oral_first_12h ON cohort.hadm_id = oral_first_12h.hadm_id
LEFT JOIN oral_final_72h ON cohort.hadm_id = oral_final_72h.hadm_id;