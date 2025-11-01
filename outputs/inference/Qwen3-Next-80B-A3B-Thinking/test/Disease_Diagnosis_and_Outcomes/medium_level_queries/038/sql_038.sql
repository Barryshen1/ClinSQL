WITH heart_failure_patients AS (
    SELECT
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.icustays` i
            WHERE i.hadm_id = a.hadm_id
        ) THEN 1 ELSE 0 END AS is_icu,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
                ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND (ddi.long_title LIKE '%chronic kidney disease%'
                     OR ddi.long_title LIKE '%ckd%'
                     OR di.icd_code LIKE 'N18%'
                     OR di.icd_code LIKE '585.%')
        ) THEN 1 ELSE 0 END AS has_ckd,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
                ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND (ddi.long_title LIKE '%diabetes%'
                     OR di.icd_code LIKE 'E1%'
                     OR di.icd_code LIKE '250.%')
        ) THEN 1 ELSE 0 END AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 80 AND 90
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
                ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND (ddi.long_title LIKE '%heart failure%'
                     OR ddi.long_title LIKE '%congestive heart failure%')
        )
)
SELECT
    is_icu,
    CASE WHEN los_days < 8 THEN '<8' ELSE '>=8' END AS los_category,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    AVG(has_ckd) * 100 AS ckd_prevalence,
    AVG(has_diabetes) * 100 AS diabetes_prevalence
FROM heart_failure_patients
GROUP BY is_icu, los_category;