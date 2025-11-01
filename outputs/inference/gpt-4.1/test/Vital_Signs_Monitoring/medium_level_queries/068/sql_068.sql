WITH map_items AS (
  -- Identify MAP itemids
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
cohort AS (
  -- Female ICU patients aged 41–51
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 41 AND 51
),
map_measurements AS (
  -- MAP measurements per ICU stay, categorized
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    CASE
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum >= 65 AND ce.valuenum < 75 THEN '65–74'
      WHEN ce.valuenum >= 75 AND ce.valuenum < 85 THEN '75–84'
      WHEN ce.valuenum >= 85 THEN '≥85'
      ELSE NULL
    END AS map_category
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM map_items)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN (
      SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = c.stay_id
    ) AND (
      SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = c.stay_id
    )
),
stroke_patients AS (
  -- Identify ICU stays with stroke diagnosis
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  WHERE (
    -- ICD-10: I60-I64
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I6[0-4]'))
    -- ICD-9: 430–434, 436
    OR (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^430')
      OR REGEXP_CONTAINS(d.icd_code, r'^431')
      OR REGEXP_CONTAINS(d.icd_code, r'^432')
      OR REGEXP_CONTAINS(d.icd_code, r'^433')
      OR REGEXP_CONTAINS(d.icd_code, r'^434')
      OR REGEXP_CONTAINS(d.icd_code, r'^436')
    ))
  )
),
map_patient_categories AS (
  -- For each ICU stay, which MAP categories did the patient have?
  SELECT DISTINCT
    subject_id,
    hadm_id,
    stay_id,
    map_category
  FROM map_measurements
  WHERE map_category IS NOT NULL
)
SELECT
  map_category,
  COUNT(DISTINCT mpc.stay_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN sp.stay_id IS NOT NULL THEN mpc.stay_id END) AS stroke_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN sp.stay_id IS NOT NULL THEN mpc.stay_id END),
    COUNT(DISTINCT mpc.stay_id)
  ) AS stroke_rate
FROM map_patient_categories mpc
LEFT JOIN stroke_patients sp
  ON mpc.stay_id = sp.stay_id
GROUP BY map_category
ORDER BY
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65–74' THEN 2
    WHEN '75–84' THEN 3
    WHEN '≥85' THEN 4
    ELSE 5
  END;