WITH cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS los_hours
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx_ugib
        ON adm.hadm_id = dx_ugib.hadm_id AND adm.subject_id = dx_ugib.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx_copd
        ON adm.hadm_id = dx_copd.hadm_id AND adm.subject_id = dx_copd.subject_id
    WHERE
        pat.anchor_age BETWEEN 69 AND 79
        AND pat.gender = 'F'
        AND dx_ugib.icd_code IN ('K250', 'K252', 'K254', 'K256', 'K260', 'K262', 'K264', 'K266', 'K270', 'K272', 'K274', 'K276', 'K280', 'K282', 'K284', 'K286')
        AND dx_ugib.icd_version = 10
        AND dx_copd.icd_code IN ('J440', 'J441')
        AND dx_copd.icd_version = 10
)
SELECT
    DISTINCT
    PERCENTILE_CONT(los_hours / 24.0, 0.5) OVER() AS median_los_days
FROM cohort;