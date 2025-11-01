WITH cohort AS (
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
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
        ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 83 AND 93
        AND d.seq_num = 1
        AND LOWER(diag.long_title) LIKE '%community-acquired pneumonia%'
)
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM cohort
WHERE los_days IS NOT NULL;