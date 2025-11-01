WITH map_itemids AS (
  -- Identify itemids that represent Mean Arterial Pressure (MAP)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
     OR LOWER(label) LIKE '%map%'
     OR LOWER(abbreviation) LIKE '%map%'
),
female_admissions AS (
  -- Female patients aged 82-92 and their admissions
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
hadm_max_map AS (
  -- For each hospital admission, compute the maximum MAP observed during the admission
  SELECT
    fa.hadm_id,
    MAX(ce.valuenum) AS max_map
  FROM female_admissions fa
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = fa.hadm_id
   AND ce.subject_id = fa.subject_id
  JOIN map_itemids m
    ON ce.itemid = m.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fa.admittime AND fa.dischtime
  GROUP BY fa.hadm_id
)
-- Return cohort size and median of per-admission maximum MAP
SELECT
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(max_map, 100)[OFFSET(50)] AS median_max_map
FROM hadm_max_map;