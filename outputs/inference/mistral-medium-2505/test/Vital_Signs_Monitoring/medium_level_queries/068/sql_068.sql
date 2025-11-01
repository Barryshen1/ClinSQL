WITH
-- Get female patients aged 41-51
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    female_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements (using common MAP itemids)
map_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_stays s ON ce.subject_id = s.subject_id AND ce.hadm_id = s.hadm_id AND ce.stay_id = s.stay_id
  WHERE
    ce.itemid IN (220050, 223121) -- MAP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg' -- Ensure units are mmHg
),

-- Get stroke diagnoses (ICD-10 codes for stroke)
stroke_diagnoses AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    icu_stays s ON d.subject_id = s.subject_id AND d.hadm_id = s.hadm_id
  WHERE
    d.icd_code LIKE 'I60%' OR
    d.icd_code LIKE 'I61%' OR
    d.icd_code LIKE 'I63%' OR
    d.icd_code = 'I64'
    AND d.icd_version = '10'
),

-- Categorize patients by MAP range and stroke status
patient_map_categories AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    CASE
      WHEN AVG(m.map_value) < 65 THEN '<65'
      WHEN AVG(m.map_value) BETWEEN 65 AND 74 THEN '65-74'
      WHEN AVG(m.map_value) BETWEEN 75 AND 84 THEN '75-84'
      WHEN AVG(m.map_value) >= 85 THEN '>=85'
    END AS map_category,
    MAX(CASE WHEN EXISTS (
      SELECT 1 FROM stroke_diagnoses s
      WHERE s.subject_id = m.subject_id AND s.hadm_id = m.hadm_id
    ) THEN 1 ELSE 0 END) AS has_stroke
  FROM
    map_measurements m
  GROUP BY
    m.subject_id, m.hadm_id, m.stay_id
)

-- Final aggregation
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  SUM(has_stroke) AS stroke_count,
  ROUND(SUM(has_stroke) * 100.0 / COUNT(DISTINCT subject_id), 2) AS stroke_rate_percentage
FROM
  patient_map_categories
GROUP BY
  map_category
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;