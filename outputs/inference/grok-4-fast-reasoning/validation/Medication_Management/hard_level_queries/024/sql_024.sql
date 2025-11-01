WITH multi_trauma AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'S%' OR icd_code LIKE 'T%')
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN multi_trauma mt ON a.hadm_id = mt.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
patient_meds AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COUNT(DISTINCT pres.drug) AS complexity,
    MAX(CASE WHEN 
      LOWER(COALESCE(pres.drug, '')) LIKE '%sertraline%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%fluoxetine%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%paroxetine%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%citalopram%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%escitalopram%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%venlafaxine%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%duloxetine%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%mirtazapine%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%trazodone%' OR
      LOWER(COALESCE(pres.drug, '')) LIKE '%tramadol%'
    THEN 1 ELSE 0 END) AS has_risk
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
with_percentiles AS (
  SELECT *,
    PERCENT_RANK() OVER (ORDER BY complexity) * 100 AS complexity_percentile
  FROM patient_meds
),
quartiles AS (
  SELECT 
    APPROX_QUANTILES(complexity, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(complexity, 4)[OFFSET(2)] AS q2,
    APPROX_QUANTILES(complexity, 4)[OFFSET(3)] AS q3
  FROM with_percentiles
),
risk_summary AS (
  SELECT 
    'Risk vs No Risk' AS section,
    CASE WHEN has_risk = 1 THEN 'Risk' ELSE 'No Risk' END AS subgroup,
    AVG(complexity_percentile) AS avg_complexity_percentile,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM with_percentiles
  GROUP BY has_risk
),
top_quartile_summary AS (
  SELECT 
    'Top Quartile' AS section,
    'Top Quartile' AS subgroup,
    NULL AS avg_complexity_percentile,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM with_percentiles
  CROSS JOIN quartiles
  WHERE complexity >= q3
),
quartiles_summary AS (
  SELECT 'Quartiles' AS section, 'Q1' AS subgroup, q1 AS avg_complexity_percentile, NULL AS avg_los_days, NULL AS mortality_rate FROM quartiles
  UNION ALL
  SELECT 'Quartiles', 'Median' AS subgroup, q2 AS avg_complexity_percentile, NULL, NULL FROM quartiles
  UNION ALL
  SELECT 'Quartiles', 'Q3' AS subgroup, q3 AS avg_complexity_percentile, NULL, NULL FROM quartiles
)
SELECT * FROM quartiles_summary
UNION ALL
SELECT * FROM risk_summary
UNION ALL
SELECT * FROM top_quartile_summary
ORDER BY section, subgroup;