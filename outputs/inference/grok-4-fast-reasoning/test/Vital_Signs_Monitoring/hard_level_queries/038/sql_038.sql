WITH se_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%status epilepticus%'
),
se_admissions AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN se_codes sc
    ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
),
base_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM se_admissions sea 
        WHERE sea.subject_id = i.subject_id AND sea.hadm_id = i.hadm_id
      ) THEN 'SE'
      ELSE 'General'
    END AS cohort
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
),
hr_data AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    COUNT(*) AS total_hr,
    SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS tach_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN base_stays bs
    ON ce.subject_id = bs.subject_id 
    AND ce.hadm_id = bs.hadm_id 
    AND ce.stay_id = bs.stay_id
  WHERE ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= bs.intime
    AND ce.charttime < DATETIME_ADD(bs.intime, INTERVAL 72 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
map_data AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    COUNT(*) AS total_map,
    SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS lowmap_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN base_stays bs
    ON ce.subject_id = bs.subject_id 
    AND ce.hadm_id = bs.hadm_id 
    AND ce.stay_id = bs.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= bs.intime
    AND ce.charttime < DATETIME_ADD(bs.intime, INTERVAL 72 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
metrics AS (
  SELECT 
    bs.cohort,
    bs.stay_id,
    bs.los,
    bs.hospital_expire_flag,
    COALESCE(hr.tach_count * 1.0 / NULLIF(hr.total_hr, 0), 0) AS tach_burden,
    COALESCE(mp.lowmap_count * 1.0 / NULLIF(mp.total_map, 0), 0) AS map_burden,
    (COALESCE(hr.tach_count * 1.0 / NULLIF(hr.total_hr, 0), 0) + 
     COALESCE(mp.lowmap_count * 1.0 / NULLIF(mp.total_map, 0), 0)) / 2 AS vital_index
  FROM base_stays bs
  LEFT JOIN hr_data hr
    ON bs.stay_id = hr.stay_id
  LEFT JOIN map_data mp
    ON bs.stay_id = mp.stay_id
)
SELECT 
  cohort,
  AVG(vital_index) AS mean_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(1)] AS p25_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(2)] AS p50_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(3)] AS p75_vital_index,
  APPROX_QUANTILES(vital_index, 10)[SAFE_OFFSET(9)] AS p90_vital_index,
  AVG(tach_burden) AS mean_tachycardia_burden,
  AVG(map_burden) AS mean_map_lt65_burden,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM metrics
WHERE cohort = 'SE'
GROUP BY cohort

UNION ALL

SELECT 
  cohort,
  AVG(vital_index) AS mean_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(1)] AS p25_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(2)] AS p50_vital_index,
  APPROX_QUANTILES(vital_index, 4)[SAFE_OFFSET(3)] AS p75_vital_index,
  APPROX_QUANTILES(vital_index, 10)[SAFE_OFFSET(9)] AS p90_vital_index,
  AVG(tach_burden) AS mean_tachycardia_burden,
  AVG(map_burden) AS mean_map_lt65_burden,
  AVG(los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM metrics
WHERE cohort = 'General'
GROUP BY cohort;