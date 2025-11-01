WITH
-- Get female patients
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),

-- Get ACS admissions (ICD-10 codes for ischemic heart diseases)
acs_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM female_patients)
    AND di.icd_code LIKE 'I2%'  -- ICD-10 codes for ischemic heart diseases (ACS)
),

-- Get troponin lab items (using only label column)
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),

-- Get nadir (minimum) troponin per admission
nadir_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.valuenum) AS min_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_itemids t ON l.itemid = t.itemid
  JOIN acs_admissions a ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE l.valuenum IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
)

-- Calculate the 25th percentile of nadir troponin values
SELECT
  PERCENTILE_CONT(nadir_troponin.min_troponin, 0.25) OVER() AS percentile_25_troponin
FROM nadir_troponin
LIMIT 1;