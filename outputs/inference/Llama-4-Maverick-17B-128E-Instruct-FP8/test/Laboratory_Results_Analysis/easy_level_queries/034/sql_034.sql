WITH hf_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age = 65 AND d_diag.long_title LIKE '%Heart failure%'
),
sodium_vals AS (
  SELECT l.hadm_id, MIN(l.valuenum) AS min_sodium
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_l ON l.itemid = d_l.itemid
  WHERE d_l.label LIKE '%Sodium%' AND d_l.fluid = 'Blood' AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
)
SELECT MIN(s.min_sodium) AS min_admission_sodium
FROM sodium_vals s
INNER JOIN hf_admissions hf ON s.hadm_id = hf.hadm_id;