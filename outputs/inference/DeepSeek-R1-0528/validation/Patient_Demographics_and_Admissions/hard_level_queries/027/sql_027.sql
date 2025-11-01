WITH eligible_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        -- Calculate age at admission: anchor_age + (current admission year - anchor_year)
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        a.admission_location = 'EMERGENCY ROOM'  -- Admitted from ED
        AND a.insurance = 'Medicare'             -- Medicare patients
),
principal_dx AS (
    SELECT 
        hadm_id,
        icd_code,
        icd_version
    FROM (
        SELECT 
            hadm_id, 
            icd_code, 
            icd_version,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    ) 
    WHERE rn = 1  -- Keep only the principal diagnosis (lowest seq_num)
)
SELECT 
    COUNT(DISTINCT ea.hadm_id) AS num_admissions
FROM eligible_admissions ea
INNER JOIN principal_dx pd
    ON ea.hadm_id = pd.hadm_id
WHERE 
    ea.gender = 'F'  -- Female patients
    AND ea.age_at_admission BETWEEN 70 AND 80  -- Age 70-80
    AND (
        (pd.icd_version = 9 AND pd.icd_code = '5770')  -- ICD-9: Acute Pancreatitis
        OR 
        (pd.icd_version = 10 AND pd.icd_code LIKE 'K85%')  -- ICD-10: Acute Pancreatitis
    );