WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.insurance,
        a.admission_type,
        p.anchor_year,
        p.anchor_age,
        -- Compute birth year and age at admission
        (p.anchor_year - p.anchor_age) AS birth_year,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND a.insurance = 'Medicare'
        AND a.admission_type = 'EMERGENCY'
),
acute_pancreatitis_admissions AS (
    SELECT 
        pa.subject_id,
        pa.hadm_id,
        pa.age_at_admission  -- Added to pass through for filtering
    FROM patient_admissions pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON pa.subject_id = d.subject_id 
        AND pa.hadm_id = d.hadm_id
    WHERE d.seq_num = 1  -- principal diagnosis
        AND d.icd_code IN (
            -- ICD-10 codes for acute pancreatitis (removed ICD-9 codes)
            'K85.0', 'K85.1', 'K85.2', 'K85.8', 'K85.9'
        )
        AND d.icd_version = 10  -- Only ICD-10 is present in MIMIC-IV
),
filtered_admissions AS (
    SELECT 
        hadm_id
    FROM acute_pancreatitis_admissions
    WHERE age_at_admission BETWEEN 72 AND 82
)
SELECT COUNT(DISTINCT hadm_id) AS total_admissions
FROM filtered_admissions;