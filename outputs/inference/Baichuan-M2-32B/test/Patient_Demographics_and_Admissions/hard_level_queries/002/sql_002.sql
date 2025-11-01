WITH principal_diagnoses AS (
    SELECT 
        subject_id, 
        hadm_id, 
        icd_code,
        seq_num,
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY seq_num ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10
),
pneumonia_diagnoses AS (
    SELECT 
        subject_id, 
        hadm_id
    FROM principal_diagnoses
    WHERE rn = 1
        AND (
            icd_code LIKE 'J10%' OR 
            icd_code LIKE 'J11%' OR 
            icd_code LIKE 'J12%' OR 
            icd_code LIKE 'J13%' OR 
            icd_code LIKE 'J15%' OR 
            icd_code LIKE 'J16%' OR 
            icd_code LIKE 'J17%' OR 
            icd_code LIKE 'J18%'
        )
)
SELECT 
    COUNT(DISTINCT a.hadm_id) AS total_index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
INNER JOIN pneumonia_diagnoses pd 
    ON a.subject_id = pd.subject_id AND a.hadm_id = pd.hadm_id
WHERE 
    p.gender = 'M'
    AND a.insurance LIKE '%Medicare%'
    AND (a.admission_location LIKE '%EMERGENCY%' OR a.admission_location LIKE '%ER%')
    AND TIMESTAMP_DIFF(
        a.admittime, 
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), 
        INTERVAL p.anchor_age YEAR), 
        YEAR
    ) BETWEEN 77 AND 87;