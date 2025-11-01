WITH
-- Identify female patients aged 82-92
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),

-- Identify admissions with chest pain or AMI
chest_pain_ami_admissions AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime
  FROM
    eligible_patients e
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON e.hadm_id = d.hadm_id
  WHERE
    -- Chest pain ICD-10 codes (R07.*)
    d.icd_code LIKE 'R07.%'
    -- AMI ICD-10 codes (I21.*, I22.*)
    OR d.icd_code LIKE 'I21.%'
    OR d.icd_code LIKE 'I22.%'
),

-- Get initial troponin T values > 0.01 ng/mL
initial_troponin AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime) AS troponin_rank
  FROM
    chest_pain_ami_admissions c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    -- Troponin T itemid (verify with d_labitems)
    di.label = 'Troponin T'
    AND l.valuenum > 0.01
    AND l.valueuom = 'ng/mL'
),

-- Calculate percentiles
percentiles AS (
  SELECT
    PERCENTILE_CONT(troponin_value, 0.25) OVER() AS p25,
    PERCENTILE_CONT(troponin_value, 0.5) OVER() AS p50,
    PERCENTILE_CONT(troponin_value, 0.75) OVER() AS p75,
    MIN(troponin_value) OVER() AS min_value,
    MAX(troponin_value) OVER() AS max_value
  FROM
    initial_troponin
  WHERE
    troponin_rank = 1  -- Only the first troponin T per admission
)

-- Final result
SELECT
  p25,
  p50,
  p75,
  min_value,
  max_value
FROM
  percentiles
LIMIT 1;