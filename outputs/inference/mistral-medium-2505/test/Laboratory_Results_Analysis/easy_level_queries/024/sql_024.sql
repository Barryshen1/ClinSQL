WITH
-- Get sepsis ICD codes (ICD-9 and ICD-10)
sepsis_icd_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
),

-- Get male patients with sepsis admissions
male_sepsis_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN sepsis_icd_codes s ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
  WHERE p.gender = 'M'
),

-- Get first platelet count per admission
first_platelet_counts AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS platelet_count,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE l.itemid = 51265  -- Platelets
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND EXISTS (
      SELECT 1
      FROM male_sepsis_admissions m
      WHERE l.subject_id = m.subject_id AND l.hadm_id = m.hadm_id
    )
)

-- Calculate SD of platelet counts
SELECT
  STDDEV(platelet_count) AS sd_platelet_count
FROM first_platelet_counts
WHERE rn = 1  -- Only the first platelet count per admission;