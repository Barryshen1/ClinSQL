WITH stroke_patients AS (
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
        AND d.seq_num = 1  -- primary diagnosis
        AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I63%') OR
            (d.icd_version = 9 AND d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '436%')
        )
        AND a.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25th_percentile
FROM stroke_patients;