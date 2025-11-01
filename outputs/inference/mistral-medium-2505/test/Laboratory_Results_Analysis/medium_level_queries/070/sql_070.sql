WITH
-- Get male patients aged 90-100 with chest pain
chest_pain_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.icd_code IN ('786.50', 'R07.9')  -- Chest pain ICD codes
),

-- Get first elevated Troponin I per admission
first_elevated_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN
    chest_pain_patients cpp
    ON l.hadm_id = cpp.hadm_id
  WHERE
    d.label = 'Troponin I'
    AND l.valuenum > l.ref_range_upper  -- Elevated Troponin I
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
)

-- Calculate statistics
SELECT
  PERCENTILE_CONT(troponin_value, 0.25) AS p25,
  PERCENTILE_CONT(troponin_value, 0.5) AS p50,
  PERCENTILE_CONT(troponin_value, 0.75) AS p75,
  MIN(troponin_value) AS min_value,
  MAX(troponin_value) AS max_value,
  MAX(troponin_value) - MIN(troponin_value) AS value_range
FROM
  first_elevated_troponin
WHERE
  rn = 1  -- Only the first elevated Troponin I per admission
LIMIT 1;