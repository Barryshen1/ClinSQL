WITH atrial_fibrillation_diagnoses AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE lower(long_title) LIKE '%atrial fibrillation%' 
  OR icd_code IN ('427.31', 'I48.0', 'I48.1', 'I48.2', 'I48.91', 'I48.92')
),
principal_diagnoses AS (
  SELECT di.hadm_id, di.icd_code, di.icd_version,
         ROW_NUMBER() OVER (PARTITION BY di.hadm_id ORDER BY di.seq_num) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN atrial_fibrillation_diagnoses afd
  ON di.icd_code = afd.icd_code AND di.icd_version = afd.icd_version
),
relevant_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 63 AND 73
  AND a.insurance = 'Medicare'
  AND a.admission_location != 'Emergency Room Admit'  -- Assuming this is the correct filter; might need adjustment based on actual values
  AND a.hadm_id IN (SELECT hadm_id FROM principal_diagnoses WHERE rn = 1)
)
SELECT COUNT(*) as total_admissions
FROM relevant_admissions;