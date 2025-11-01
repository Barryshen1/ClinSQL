WITH
-- Filter female patients aged 58-68
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),

-- Get admissions with chest pain or AMI
relevant_admissions AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN eligible_patients p
    ON a.subject_id = p.subject_id
  WHERE d.icd_code IN (
    -- Chest pain ICD-10 codes (R07.1-R07.9)
    'R071', 'R072', 'R073', 'R074', 'R078', 'R079',
    -- AMI ICD-10 codes (I21.x)
    'I210', 'I211', 'I212', 'I213', 'I214', 'I219'
  )
    AND d.icd_version = 10
),

-- Get first Troponin T > 0.01 ng/mL per admission
first_high_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN relevant_admissions a
    ON l.subject_id = a.subject_id AND l.hadm_id = a.hadm_id
  WHERE d.label = 'Troponin T'
    AND l.valuenum > 0.01
    AND l.valueuom = 'ng/mL'
)

-- Calculate distribution statistics
SELECT
  AVG(valuenum) AS mean_troponin,
  STDDEV(valuenum) AS sd_troponin,
  MIN(valuenum) AS min_troponin,
  MAX(valuenum) AS max_troponin
FROM first_high_troponin
WHERE rn = 1;  -- Only the first high Troponin T per admission;