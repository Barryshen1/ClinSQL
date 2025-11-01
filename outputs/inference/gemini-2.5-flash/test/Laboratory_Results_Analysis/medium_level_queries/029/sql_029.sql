WITH cohort_diagnoses AS (
    -- Identify admissions with Chest Pain or AMI diagnosis
    SELECT DISTINCT di.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE
        (
            di.icd_version = 9 AND (di.icd_code LIKE '410%' OR di.icd_code LIKE '786.5%') -- ICD-9 for AMI or Chest Pain
        )
        OR
        (
            di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'R07%') -- ICD-10 for AMI or Chest Pain
        )
),
initial_troponin AS (
    -- Get the first Troponin T value for each admission
    SELECT
        le.hadm_id,
        le.valuenum AS first_troponin_t_val
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.itemid = 51003 -- itemid for Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valueuom = 'ng/mL'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
-- Main query to calculate summary statistics for the defined cohort
SELECT
    COUNT(ad.hadm_id) AS total_admissions_in_cohort,
    COUNTIF(ad.hospital_expire_flag = 1) AS in_hospital_deaths,
    SAFE_DIVIDE(COUNTIF(ad.hospital_expire_flag = 1), COUNT(ad.hadm_id)) AS in_hospital_mortality_rate
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` ad
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND ad.hadm_id IN (SELECT hadm_id FROM cohort_diagnoses)
    AND ad.hadm_id IN (SELECT hadm_id FROM initial_troponin WHERE first_troponin_t_val > 0.04);