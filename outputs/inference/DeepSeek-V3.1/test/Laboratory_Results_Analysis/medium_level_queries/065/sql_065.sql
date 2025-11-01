WITH ami_patients AS (
    SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
        AND di.icd_version = 10
        AND (dd.long_title LIKE 'Acute myocardial infarction%' 
             OR di.icd_code LIKE 'I21%' 
             OR di.icd_code LIKE 'I22%')
),
first_troponin AS (
    SELECT 
        ap.subject_id,
        ap.hadm_id,
        le.valuenum AS troponin_value,
        ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime) AS rn
    FROM ami_patients ap
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 51003 -- Troponin T
        AND le.valuenum > 0.04
        AND le.valueuom = 'ng/mL'
)
SELECT 
    APPROX_QUANTILES(troponin_value, 4)[OFFSET(2)] AS median_troponin,
    APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS q1_troponin,
    APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS q3_troponin
FROM first_troponin
WHERE rn = 1;