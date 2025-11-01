WITH cohort AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 37 AND 47
        AND d.seq_num = 1
        AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
            OR
            (d.icd_version = 9 AND d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%')
        )
        AND a.dischtime IS NOT NULL
)
SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM cohort;