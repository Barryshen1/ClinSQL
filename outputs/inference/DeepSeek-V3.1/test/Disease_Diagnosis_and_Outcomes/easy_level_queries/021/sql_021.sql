WITH target_cohort AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pt.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx1
        ON adm.hadm_id = dx1.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx2
        ON adm.hadm_id = dx2.hadm_id
    WHERE
        pt.gender = 'F'
        AND pt.anchor_age BETWEEN 58 AND 68
        AND dx1.icd_code LIKE 'I6[0-2]%' AND dx1.icd_version = 10
        AND dx2.icd_code = 'J44.1' AND dx2.icd_version = 10
        AND adm.dischtime IS NOT NULL
)
SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3,
    COUNT(*) AS n
FROM target_cohort;