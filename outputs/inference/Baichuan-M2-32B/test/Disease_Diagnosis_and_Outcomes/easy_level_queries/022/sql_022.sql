WITH eligible_admissions AS (
    SELECT
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id
        AND a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81
        AND d.icd_code LIKE 'I63%'  -- ICD-10 code for ischemic stroke
        AND d.seq_num = 1  -- primary diagnosis
        AND a.dischtime IS NOT NULL  -- exclude incomplete admissions
)
SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM eligible_admissions;