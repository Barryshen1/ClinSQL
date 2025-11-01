WITH qualifying_diabetes_admissions AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14'))
        OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250')
),
qualifying_hf_admissions AS (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
        OR (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
),
cohort_admissions AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        pat.gender,
        pat.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN qualifying_diabetes_admissions AS d_diag
        ON adm.subject_id = d_diag.subject_id AND adm.hadm_id = d_diag.hadm_id
    INNER JOIN qualifying_hf_admissions AS hf_diag
        ON adm.subject_id = hf_diag.subject_id AND adm.hadm_id = hf_diag.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 77 AND 87
        AND adm.dischtime IS NOT NULL
        AND adm.dischtime > adm.admittime -- Ensure valid admission duration
),
medication_flags AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        ca.dischtime,
        -- Flag for any insulin between admittime and admittime + 48 hours
        MAX(CASE
            WHEN px.starttime >= ca.admittime
            AND px.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
            AND (LOWER(px.drug) LIKE '%insulin%')
            THEN 1
            ELSE 0
        END) AS insulin_0_48h_flag,
        -- Flag for any oral agent between admittime and admittime + 48 hours
        MAX(CASE
            WHEN px.starttime >= ca.admittime
            AND px.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
            AND (
                   LOWER(px.drug) LIKE '%metformin%' OR LOWER(px.drug) LIKE '%glipizide%'
                OR LOWER(px.drug) LIKE '%glyburide%' OR LOWER(px.drug) LIKE '%sitagliptin%'
                OR LOWER(px.drug) LIKE '%saxagliptin%' OR LOWER(px.drug) LIKE '%linagliptin%'
                OR LOWER(px.drug) LIKE '%alogliptin%' OR LOWER(px.drug) LIKE '%rosiglitazone%'
                OR LOWER(px.drug) LIKE '%pioglitazone%' OR LOWER(px.drug) LIKE '%repaglinide%'
                OR LOWER(px.drug) LIKE '%nateglinide%' OR LOWER(px.drug) LIKE '%canagliflozin%'
                OR LOWER(px.drug) LIKE '%dapagliflozin%' OR LOWER(px.drug) LIKE '%empagliflozin%'
                OR LOWER(px.drug) LIKE '%acarbose%' OR LOWER(px.drug) LIKE '%miglitol%'
            )
            AND LOWER(px.drug) NOT LIKE '%insulin%' -- Exclude insulin from oral agents
            THEN 1
            ELSE 0
        END) AS oral_0_48h_flag,
        -- Flag for any insulin between dischtime - 72 hours and dischtime
        -- Only consider admissions with a duration of at least 72 hours for this window
        MAX(CASE
            WHEN DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) >= 72
            AND px.starttime >= DATETIME_SUB(ca.dischtime, INTERVAL 72 HOUR)
            AND px.starttime <= ca.dischtime
            AND (LOWER(px.drug) LIKE '%insulin%')
            THEN 1
            ELSE 0
        END) AS insulin_final_72h_flag,
        -- Flag for any oral agent between dischtime - 72 hours and dischtime
        MAX(CASE
            WHEN DATETIME_DIFF(ca.dischtime, ca.admittime, HOUR) >= 72
            AND px.starttime >= DATETIME_SUB(ca.dischtime, INTERVAL 72 HOUR)
            AND px.starttime <= ca.dischtime
            AND (
                   LOWER(px.drug) LIKE '%metformin%' OR LOWER(px.drug) LIKE '%glipizide%'
                OR LOWER(px.drug) LIKE '%glyburide%' OR LOWER(px.drug) LIKE '%sitagliptin%'
                OR LOWER(px.drug) LIKE '%saxagliptin%' OR LOWER(px.drug) LIKE '%linagliptin%'
                OR LOWER(px.drug) LIKE '%alogliptin%' OR LOWER(px.drug) LIKE '%rosiglitazone%'
                OR LOWER(px.drug) LIKE '%pioglitazone%' OR LOWER(px.drug) LIKE '%repaglinide%'
                OR LOWER(px.drug) LIKE '%nateglinide%' OR LOWER(px.drug) LIKE '%canagliflozin%'
                OR LOWER(px.drug) LIKE '%dapagliflozin%' OR LOWER(px.drug) LIKE '%empagliflozin%'
                OR LOWER(px.drug) LIKE '%acarbose%' OR LOWER(px.drug) LIKE '%miglitol%'
            )
            AND LOWER(px.drug) NOT LIKE '%insulin%'
            THEN 1
            ELSE 0
        END) AS oral_final_72h_flag
    FROM cohort_admissions AS ca
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS px
        ON ca.subject_id = px.subject_id AND ca.hadm_id = px.hadm_id
    GROUP BY ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime
),
summary_stats AS (
    SELECT
        COUNT(DISTINCT subject_id) AS total_cohort_patients,
        -- Number of patients exposed in 0-48h window
        SUM(insulin_0_48h_flag) AS insulin_0_48h_patients,
        SUM(oral_0_48h_flag) AS oral_0_48h_patients,
        -- Number of patients exposed in final 72h window
        SUM(insulin_final_72h_flag) AS insulin_final_72h_patients,
        SUM(oral_final_72h_flag) AS oral_final_72h_patients
    FROM medication_flags
)
SELECT
    -- Initiation rates (defined as percentage of patients receiving drug within the window)
    ROUND((s.insulin_0_48h_patients * 100.0 / s.total_cohort_patients), 2) AS insulin_rate_0_48h_pct,
    ROUND((s.oral_0_48h_patients * 100.0 / s.total_cohort_patients), 2) AS oral_rate_0_48h_pct,
    ROUND((s.insulin_final_72h_patients * 100.0 / s.total_cohort_patients), 2) AS insulin_rate_final_72h_pct,
    ROUND((s.oral_final_72h_patients * 100.0 / s.total_cohort_patients), 2) AS oral_rate_final_72h_pct,
    -- Net Change (percentage points)
    ROUND(
        (s.insulin_final_72h_patients * 100.0 / s.total_cohort_patients) -
        (s.insulin_0_48h_patients * 100.0 / s.total_cohort_patients), 2
    ) AS insulin_net_change_pp,
    ROUND(
        (s.oral_final_72h_patients * 100.0 / s.total_cohort_patients) -
        (s.oral_0_48h_patients * 100.0 / s.total_cohort_patients), 2
    ) AS oral_net_change_pp
FROM summary_stats AS s;