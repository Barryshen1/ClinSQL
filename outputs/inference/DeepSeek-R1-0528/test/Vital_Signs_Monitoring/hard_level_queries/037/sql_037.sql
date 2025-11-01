WITH first_icu_stays AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1
),
heart_failure_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') OR 
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
hr_agg AS (
  SELECT 
    ie.stay_id,
    COUNT(ce.valuenum) AS hr_count,
    SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_abnormal
  FROM first_icu_stays ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
    AND ce.itemid IN (220045, 211)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  GROUP BY ie.stay_id
),
map_agg AS (
  SELECT 
    ie.stay_id,
    COUNT(ce.valuenum) AS map_count,
    SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_abnormal
  FROM first_icu_stays ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
    AND ce.itemid IN (220181, 456, 52, 6702)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  GROUP BY ie.stay_id
),
rr_agg AS (
  SELECT 
    ie.stay_id,
    COUNT(ce.valuenum) AS rr_count,
    SUM(CASE WHEN ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_abnormal
  FROM first_icu_stays ie
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
    AND ce.itemid IN (220210, 618, 615, 224690)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 72 HOUR)
  GROUP BY ie.stay_id
),
vitals_72h AS (
  SELECT 
    ie.stay_id,
    COALESCE(hr.hr_count, 0) AS hr_count,
    COALESCE(hr.hr_abnormal, 0) AS hr_abnormal,
    COALESCE(map.map_count, 0) AS map_count,
    COALESCE(map.map_abnormal, 0) AS map_abnormal,
    COALESCE(rr.rr_count, 0) AS rr_count,
    COALESCE(rr.rr_abnormal, 0) AS rr_abnormal
  FROM first_icu_stays ie
  LEFT JOIN hr_agg hr ON ie.stay_id = hr.stay_id
  LEFT JOIN map_agg map ON ie.stay_id = map.stay_id
  LEFT JOIN rr_agg rr ON ie.stay_id = rr.stay_id
  WHERE 
    COALESCE(hr.hr_count, 0) > 0 
    AND COALESCE(map.map_count, 0) > 0 
    AND COALESCE(rr.rr_count, 0) > 0
),
cohort_with_scores AS (
  SELECT 
    v.stay_id,
    f.gender,
    f.age,
    f.los,
    f.hadm_id,
    f.hospital_expire_flag,
    v.hr_abnormal / v.hr_count AS prop_hr_abnormal,
    v.map_abnormal / v.map_count AS prop_map_abnormal,
    v.rr_abnormal / v.rr_count AS prop_rr_abnormal,
    (v.hr_abnormal / v.hr_count) + 
    (v.map_abnormal / v.map_count) + 
    (v.rr_abnormal / v.rr_count) AS composite_score
  FROM vitals_72h v
  INNER JOIN first_icu_stays f
    ON v.stay_id = f.stay_id
),
heart_failure_cohort AS (
  SELECT 
    c.*
  FROM cohort_with_scores c
  INNER JOIN heart_failure_admissions hf
    ON c.hadm_id = hf.hadm_id
  WHERE 
    c.gender = 'M' 
    AND c.age BETWEEN 45 AND 55
),
p99 AS (
  SELECT 
    APPROX_QUANTILES(composite_score, 100)[OFFSET(99)] AS p99_composite
  FROM heart_failure_cohort
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY composite_score DESC) AS quartile
  FROM heart_failure_cohort
),
most_unstable AS (
  SELECT 
    'Most Unstable Quartile (Heart Failure)' AS group_name,
    AVG(prop_hr_abnormal) AS avg_tachycardia,
    AVG(prop_map_abnormal) AS avg_hypotension,
    AVG(prop_rr_abnormal) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM quartiles
  WHERE quartile = 1
),
icu_population AS (
  SELECT 
    'Entire ICU Population' AS group_name,
    AVG(prop_hr_abnormal) AS avg_tachycardia,
    AVG(prop_map_abnormal) AS avg_hypotension,
    AVG(prop_rr_abnormal) AS avg_tachypnea,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_with_scores
)
SELECT 
  '99th Percentile (Heart Failure)' AS group_name,
  NULL AS avg_tachycardia,
  NULL AS avg_hypotension,
  NULL AS avg_tachypnea,
  NULL AS avg_los,
  NULL AS mortality_rate,
  p99_composite AS composite_99th_percentile
FROM p99
UNION ALL
SELECT 
  group_name,
  avg_tachycardia,
  avg_hypotension,
  avg_tachypnea,
  avg_los,
  mortality_rate,
  NULL AS composite_99th_percentile
FROM most_unstable
UNION ALL
SELECT 
  group_name,
  avg_tachycardia,
  avg_hypotension,
  avg_tachypnea,
  avg_los,
  mortality_rate,
  NULL AS composite_99th_percentile
FROM icu_population;