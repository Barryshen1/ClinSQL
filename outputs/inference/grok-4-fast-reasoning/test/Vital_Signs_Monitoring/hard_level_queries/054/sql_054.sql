WITH arf_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '51881')
     OR (icd_version = 10 AND (icd_code LIKE 'J96.0%' OR icd_code LIKE 'J96.2%'))
),
map_burden AS (
  SELECT 
    ce.stay_id,
    SUM(CASE WHEN ce.valuenum < 65 THEN 1.0 ELSE 0 END) / COUNT(*) AS burden_map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY ce.stay_id
),
hr_burden AS (
  SELECT 
    ce.stay_id,
    SUM(CASE WHEN ce.valuenum > 100 THEN 1.0 ELSE 0 END) / COUNT(*) AS burden_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.stay_id = i.stay_id
  WHERE ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY ce.stay_id
),
burdens AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    COALESCE(m.burden_map, 0.0) AS burden_map,
    COALESCE(h.burden_hr, 0.0) AS burden_hr,
    COALESCE(m.burden_map, 0.0) + COALESCE(h.burden_hr, 0.0) AS composite,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN map_burden m ON i.stay_id = m.stay_id
  LEFT JOIN hr_burden h ON i.stay_id = h.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
flagged AS (
  SELECT 
    b.*,
    CASE 
      WHEN p.gender = 'M' 
           AND p.anchor_age BETWEEN 82 AND 92 
           AND arf.hadm_id IS NOT NULL 
      THEN 1 
      ELSE 0 
    END AS is_cohort
  FROM burdens b
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON b.subject_id = p.subject_id
  LEFT JOIN arf_hadms arf ON b.hadm_id = arf.hadm_id
)
SELECT 
  'Cohort' AS population,
  APPROX_QUANTILES(composite, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(composite, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(composite, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(composite, 100)[OFFSET(75)] - APPROX_QUANTILES(composite, 100)[OFFSET(25)] AS IQR,
  AVG(burden_map) AS avg_map_burden,
  AVG(burden_hr) AS avg_hr_burden,
  AVG(los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM flagged 
WHERE is_cohort = 1

UNION ALL

SELECT 
  'General ICU' AS population,
  CAST(NULL AS FLOAT64) AS p25,
  CAST(NULL AS FLOAT64) AS median,
  CAST(NULL AS FLOAT64) AS p75,
  CAST(NULL AS FLOAT64) AS IQR,
  AVG(burden_map) AS avg_map_burden,
  AVG(burden_hr) AS avg_hr_burden,
  AVG(los) AS avg_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM flagged 
WHERE is_cohort = 0;