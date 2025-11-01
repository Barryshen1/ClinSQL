WITH septic AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '785.52')
     OR (icd_version = 10 AND icd_code = 'R65.21')
),
cardio AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code = '785.51')
     OR (icd_version = 10 AND icd_code = 'R57.0')
),
cohort AS (
  SELECT 
    icu.stay_id, icu.subject_id, icu.hadm_id, icu.intime, icu.los,
    pat.gender, pat.anchor_age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN septic s 
    ON icu.subject_id = s.subject_id AND icu.hadm_id = s.hadm_id
  INNER JOIN cardio ca 
    ON icu.subject_id = ca.subject_id AND icu.hadm_id = ca.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age >= 60 
    AND pat.anchor_age <= 70
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime ASC) = 1
),
map_obs AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS total_map,
    COUNTIF(ce.valuenum < 65) AS low_map
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 48 HOUR
    AND ce.itemid IN (456, 5524)
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
hr_obs AS (
  SELECT 
    c.stay_id,
    COUNT(*) AS total_hr,
    COUNTIF(ce.valuenum > 100) AS high_hr
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = c.stay_id
  WHERE ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 48 HOUR
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
scores AS (
  SELECT 
    co.stay_id, co.los, co.hospital_expire_flag,
    COALESCE(m.total_map, 0) AS total_map,
    COALESCE(m.low_map, 0) AS low_map,
    COALESCE(h.total_hr, 0) AS total_hr,
    COALESCE(h.high_hr, 0) AS high_hr
  FROM cohort co
  LEFT JOIN map_obs m ON co.stay_id = m.stay_id
  LEFT JOIN hr_obs h ON co.stay_id = h.stay_id
),
instability AS (
  SELECT *,
    SAFE_DIVIDE(low_map, total_map) AS hypo_frac,
    SAFE_DIVIDE(high_hr, total_hr) AS tachy_frac,
    (SAFE_DIVIDE(low_map, total_map) + SAFE_DIVIDE(high_hr, total_hr)) / 2 AS instability_score
  FROM scores
),
stats AS (
  SELECT 
    'Cohort' AS group_type,
    ROUND(APPROX_QUANTILES(instability_score, 100)[OFFSET(95)], 4) AS instability_95th,
    ROUND(AVG(hypo_frac) * 100, 2) AS mean_hypotension_pct,
    ROUND(AVG(tachy_frac) * 100, 2) AS mean_tachycardia_pct,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
  FROM instability
  
  UNION ALL
  
  SELECT 
    'Top Decile' AS group_type,
    NULL AS instability_95th,
    ROUND(AVG(hypo_frac) * 100, 2) AS mean_hypotension_pct,
    ROUND(AVG(tachy_frac) * 100, 2) AS mean_tachycardia_pct,
    ROUND(AVG(los), 2) AS mean_icu_los_days,
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct
  FROM instability i
  CROSS JOIN (SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90 FROM instability) p
  WHERE i.instability_score >= p.p90
)
SELECT * FROM stats
ORDER BY CASE WHEN group_type = 'Cohort' THEN 1 ELSE 2 END;