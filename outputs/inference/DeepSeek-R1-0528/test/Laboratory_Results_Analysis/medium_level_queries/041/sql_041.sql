WITH acs_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code IN ('4111', '41181')))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I23%' OR d.icd_code IN ('I200', 'I240', 'I248', 'I249')))
    )
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),
troponin_tests AS (
  SELECT
    l.hadm_id,
    l.charttime,
    l.valuenum,
    SAFE_CAST(l.ref_range_upper AS FLOAT64) AS uln
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON aa.hadm_id = l.hadm_id
  WHERE
    l.itemid = 51003  -- hs-Troponin T
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),
first_troponin AS (
  SELECT
    hadm_id,
    valuenum,
    uln
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM troponin_tests
  )
  WHERE rn = 1
),
filtered_troponin AS (
  SELECT
    valuenum
  FROM first_troponin
  WHERE valuenum > uln
),
quantiles AS (
  SELECT
    APPROX_QUANTILES(valuenum, 100) AS percentiles
  FROM filtered_troponin
)
SELECT
  percentiles[OFFSET(50)] AS median_initial_troponin_ng_per_ml,
  percentiles[OFFSET(75)] - percentiles[OFFSET(25)] AS iqr_initial_troponin_ng_per_ml
FROM quantiles;