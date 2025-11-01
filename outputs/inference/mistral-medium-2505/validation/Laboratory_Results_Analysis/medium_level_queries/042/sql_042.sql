WITH
-- Define chest pain ICD codes (ICD-10)
chest_pain_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND icd_code IN ('R07.1', 'R07.2', 'R07.3', 'R07.4', 'R07.9')
),

-- Get female patients aged 84-94 with chest pain admission
female_patients_chest_pain AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN chest_pain_icd c ON d.icd_code = c.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
),

-- Get first troponin T measurement per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM female_patients_chest_pain)
    AND d.label = 'Troponin T'
    AND l.valuenum IS NOT NULL
),

-- Classify troponin T levels
troponin_classification AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 0.01 THEN 'Normal'
      WHEN valuenum BETWEEN 0.01 AND 0.03 THEN 'Borderline'
      WHEN valuenum > 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1  -- First troponin per admission
),

-- Combine with mortality data
final_data AS (
  SELECT
    t.troponin_category,
    COUNT(*) AS count,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count
  FROM troponin_classification t
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON t.hadm_id = a.hadm_id
  GROUP BY t.troponin_category
)

-- Calculate percentages and final output
SELECT
  troponin_category,
  count,
  ROUND(count * 100.0 / SUM(count) OVER (), 2) AS percentage,
  mortality_count,
  ROUND(mortality_count * 100.0 / count, 2) AS mortality_percentage
FROM final_data
ORDER BY count DESC;