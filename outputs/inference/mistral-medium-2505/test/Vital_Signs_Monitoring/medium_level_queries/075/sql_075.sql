WITH
-- Get male patients aged 56-66
male_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 56 AND 66
),

-- Get ICU stays for these patients
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
    male_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements (using common itemids for MAP)
map_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE
    ce.itemid IN (220050, 220051)  -- MAP and MAP Invasive itemids
    AND ce.valuenum IS NOT NULL
),

-- Calculate average MAP per stay
avg_map_per_stay AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    AVG(m.map_value) AS avg_map
  FROM
    map_measurements m
  GROUP BY
    m.subject_id, m.hadm_id, m.stay_id
),

-- Categorize MAP into groups
map_categories AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    CASE
      WHEN a.avg_map < 65 THEN '<65'
      WHEN a.avg_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN a.avg_map BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM
    avg_map_per_stay a
),

-- Identify stroke diagnoses (using common stroke ICD-10 codes)
stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_code LIKE 'I60%' OR
    d.icd_code LIKE 'I61%' OR
    d.icd_code LIKE 'I63%' OR
    d.icd_code LIKE 'I64%' OR
    d.icd_code LIKE 'G45%' OR
    d.icd_code LIKE 'G46%' OR
    d.icd_code LIKE 'H34.1%' OR
    d.icd_code LIKE 'H34.2%'
),

-- Combine all data
final_data AS (
  SELECT
    m.map_category,
    COUNT(DISTINCT m.subject_id) AS patient_count,
    COUNT(DISTINCT s.subject_id) AS stroke_count
  FROM
    map_categories m
  LEFT JOIN
    stroke_patients s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id
  GROUP BY
    m.map_category
)

-- Calculate stroke rates
SELECT
  map_category,
  patient_count,
  stroke_count,
  ROUND((stroke_count / patient_count) * 100, 2) AS stroke_rate_percentage
FROM
  final_data
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    ELSE 4
  END;