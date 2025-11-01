WITH heart_failure_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND (
      LOWER(did.long_title) LIKE '%heart failure%'
      OR d.icd_code IN (
        '428.0', '428.1', '428.2', '428.3', '428.4', '428.9',  -- ICD-9
        'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'   -- ICD-10
      )
    )
),
nadir_hemoglobin AS (
  SELECT 
    hfa.hadm_id,
    MIN(le.valuenum) AS nadir_hemoglobin
  FROM heart_failure_admissions hfa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON hfa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE dli.label IN ('Hemoglobin', 'Hgb', 'Hb')
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0  -- Exclude implausible negative or zero values
  GROUP BY hfa.hadm_id
)
SELECT 
  PERCENTILE_CONT(nadir_hemoglobin, 0.75) AS p75_nadir_hemoglobin
FROM nadir_hemoglobin;