WITH pneumonia_cohort AS (
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
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id AND a.subject_id = di.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 88 AND 98
        AND a.admission_type = 'EMERGENCY'
        AND di.seq_num = 1
        AND (
            -- ICD-9 codes for pneumonia
            (di.icd_version = 9 AND di.icd_code LIKE '480%' OR di.icd_code = '481' OR di.icd_code LIKE '482%' OR di.icd_code LIKE '483%' OR di.icd_code = '485' OR di.icd_code = '486')
            OR
            -- ICD-10 codes for pneumonia
            (di.icd_version = 10 AND (di.icd_code LIKE 'J12%' OR di.icd_code = 'J13' OR di.icd_code = 'J14' OR di.icd_code LIKE 'J15%' OR di.icd_code LIKE 'J16%' OR di.icd_code LIKE 'J18%'))
        )
        AND a.dischtime IS NOT NULL  -- exclude ongoing admissions
)
SELECT
    MIN(los_days) AS min_los_days
FROM pneumonia_cohort;