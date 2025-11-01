WITH sepsis_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code IN ('99591', '99592')))
        OR
        (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%'))
),
eligible_admissions AS (
    SELECT 
        a.hadm_id,
        p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 90 AND 100
)
SELECT 
    STDDEV_POP(i.los) AS std_icu_los
FROM eligible_admissions e
INNER JOIN sepsis_admissions s
    ON e.hadm_id = s.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON e.hadm_id = i.hadm_id;