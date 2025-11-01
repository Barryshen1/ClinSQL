WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.hospital_expire_flag,
        pat.anchor_age,
        -- Get the first Troponin T value per admission
        FIRST_VALUE(le.valuenum) OVER (
            PARTITION BY adm.hadm_id 
            ORDER BY le.charttime
        ) AS first_troponin_t
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.hadm_id = le.hadm_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 58 AND 68
        AND (
            -- Chest pain ICD codes
            (diag.icd_version = 10 AND diag.icd_code LIKE 'R07%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '786.5%') OR
            -- AMI ICD codes
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%') OR
            (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        )
        -- Troponin T itemid
        AND le.itemid = 51003
)
SELECT 
    COUNT(*) AS num_admissions,
    COUNT(DISTINCT subject_id) AS num_patients,
    ROUND(AVG(anchor_age), 1) AS mean_age,
    SUM(hospital_expire_flag) AS num_in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_percent,
    ROUND(MIN(first_troponin_t), 3) AS min_first_troponin,
    ROUND(MAX(first_troponin_t), 3) AS max_first_troponin,
    ROUND(AVG(first_troponin_t), 3) AS avg_first_troponin
FROM cohort
WHERE first_troponin_t > 0.04;