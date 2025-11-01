WITH HeartFailureAdmissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-10 codes for Heart Failure
        (icd_version = 10 AND icd_code LIKE 'I50%')
        OR
        -- ICD-9 codes for Heart Failure
        (icd_version = 9 AND icd_code LIKE '428%')
),
COPDAdmissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-10 codes for COPD
        (icd_version = 10 AND icd_code LIKE 'J44%')
        OR
        -- ICD-9 codes for COPD
        (icd_version = 9 AND (icd_code LIKE '491%' OR icd_code LIKE '492%' OR icd_code = '496'))
),
CohortLOS AS ( -- This is the definition of the CTE
    SELECT
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days -- LOS in fractional days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        HeartFailureAdmissions AS hf
        ON ad.hadm_id = hf.hadm_id
    INNER JOIN
        COPDAdmissions AS copd
        ON ad.hadm_id = copd.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 77 AND 87
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 IS NOT NULL
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 >= 0 -- Ensure positive LOS, though typically it is.
)
-- Final SELECT statement to answer the question
SELECT
    STDDEV(los_days) AS standard_deviation_of_hospital_los_days
FROM
    CohortLOS;