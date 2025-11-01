WITH orders AS (
  -- prescriptions table
  SELECT
    subject_id,
    hadm_id,
    drug AS drug_name,
    route,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL
    AND stoptime IS NOT NULL

  UNION ALL

  -- pharmacy table (additional source of hospital medication orders)
  SELECT
    subject_id,
    hadm_id,
    medication AS drug_name,
    route,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
    AND stoptime IS NOT NULL
),

nitrate_orders AS (
  -- identify likely nitrate medications by name pattern
  SELECT
    o.*,
    CAST(TIMESTAMP_DIFF(o.stoptime, o.starttime, MINUTE) AS FLOAT64) / 1440.0 AS duration_days
  FROM orders o
  WHERE LOWER(COALESCE(o.drug_name, '')) LIKE '%nitro%'
     OR LOWER(COALESCE(o.drug_name, '')) LIKE '%isosorbide%'
     OR REGEXP_CONTAINS(LOWER(COALESCE(o.drug_name, '')), r'\bntg\b')
),

inpatient_nitrate_orders AS (
  -- restrict to female inpatients aged 80-90 and relevant routes (IV/oral/sublingual)
  SELECT
    n.subject_id,
    n.hadm_id,
    n.drug_name,
    n.route,
    n.starttime,
    n.stoptime,
    n.duration_days,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM nitrate_orders n
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON n.subject_id = a.subject_id
   AND n.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON n.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    -- ensure prescription started during the hospital admission (inpatient)
    AND n.starttime >= a.admittime
    AND n.starttime <= a.dischtime
    -- positive duration only
    AND n.stoptime > n.starttime
    -- route is IV, oral, or sublingual (case-insensitive, handles variants)
    AND REGEXP_CONTAINS(LOWER(COALESCE(n.route, '')), r'(iv|intravenous|oral|subling)')
)

SELECT
  MAX(duration_days) AS max_duration_days,
  MAX(duration_days) * 24.0 AS max_duration_hours
FROM inpatient_nitrate_orders;