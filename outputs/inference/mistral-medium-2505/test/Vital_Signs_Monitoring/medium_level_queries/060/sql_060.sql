WITH
-- Get female patients aged 70-80
female_patients_70_80 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 70 AND 80
),

-- Get their first ICU stays
first_icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    ROW_NUMBER() OVER (PARTITION BY s.subject_id, s.hadm_id ORDER BY s.intime) AS stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients_70_80 p ON s.subject_id = p.subject_id
  WHERE
    s.stay_id IS NOT NULL
),

-- Get max SBP in first 24 hours for each stay
max_sbp_first_24h AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON f.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    f.stay_rank = 1  -- Only first ICU stay per admission
    AND di.label = 'Systolic Blood Pressure'
    AND ce.charttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id
),

-- Categorize patients by SBP
sbp_categories AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN max_sbp < 130 THEN '<130'
      WHEN max_sbp BETWEEN 130 AND 139 THEN '130-139'
      WHEN max_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN max_sbp >= 160 THEN '>=160'
      ELSE NULL
    END AS sbp_category
  FROM
    max_sbp_first_24h
  WHERE
    max_sbp IS NOT NULL
),

-- Identify stroke patients
stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code IN (
      'I63', 'I61', 'I60', 'I62', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69',
      'G45', 'G46', 'H34', 'H34.0', 'H34.1', 'H34.2', 'H34.3', 'H34.8', 'H34.9'
    )
    AND d.icd_version = 10  -- ICD-10 codes
),

-- Combine all information
final_data AS (
  SELECT
    sc.sbp_category,
    COUNT(DISTINCT sc.subject_id) AS total_patients,
    COUNT(DISTINCT sp.subject_id) AS stroke_patients,
    COUNT(DISTINCT sp.subject_id) * 100.0 / COUNT(DISTINCT sc.subject_id) AS stroke_rate
  FROM
    sbp_categories sc
  LEFT JOIN
    stroke_patients sp ON sc.subject_id = sp.subject_id AND sc.hadm_id = sp.hadm_id
  GROUP BY
    sc.sbp_category
)

-- Final output
SELECT
  sbp_category,
  total_patients,
  ROUND(total_patients * 100.0 / SUM(total_patients) OVER(), 2) AS percentage,
  stroke_patients,
  ROUND(stroke_rate, 2) AS stroke_rate_percentage
FROM
  final_data
ORDER BY
  CASE sbp_category
    WHEN '<130' THEN 1
    WHEN '130-139' THEN 2
    WHEN '140-159' THEN 3
    WHEN '>=160' THEN 4
    ELSE 5
  END;