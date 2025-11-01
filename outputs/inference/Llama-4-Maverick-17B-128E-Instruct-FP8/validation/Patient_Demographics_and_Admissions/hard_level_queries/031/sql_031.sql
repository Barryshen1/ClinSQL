WITH patient_age AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.admission_location,
    a.insurance
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),
principal_diagnosis AS (
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
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ) sub
  WHERE rn = 1
)
SELECT 
  COUNT(DISTINCT pa.hadm_id) AS num_index_admissions
FROM 
  patient_age pa
INNER JOIN 
  principal_diagnosis pd ON pa.hadm_id = pd.hadm_id
WHERE 
  pa.age_at_admission BETWEEN 62 AND 72
  AND pa.gender = 'F'
  AND pa.admission_location = 'EMERGENCY ROOM ADMIT'
  AND pa.insurance = 'Medicare'
  AND ((pd.icd_version = 9 AND pd.icd_code = '7802') OR (pd.icd_version = 10 AND pd.icd_code = 'R55'));