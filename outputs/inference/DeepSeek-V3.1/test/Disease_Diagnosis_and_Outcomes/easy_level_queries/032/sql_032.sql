WITH akd_patients AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 81 AND 91
        AND d.seq_num = 1  -- primary diagnosis
        AND d.icd_version = 10
        AND d.icd_code LIKE 'N17%'  -- acute kidney injury
        AND a.dischtime IS NOT NULL  -- ensure discharged
)
SELECT 
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(los_days, 4)[OFFSET(2)] AS median,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM akd_patients;