WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) AS end_72h,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

lab_values AS (
  SELECT 
    c.hadm_id,
    d.label,
    le.valuenum,
    le.charttime
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON c.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON le.itemid = d.itemid
  WHERE le.charttime >= c.admittime 
    AND le.charttime <= c.end_72h
    AND le.valuenum IS NOT NULL
    AND d.label IN (
      'Creatinine',
      'Potassium',
      'Platelet Count',
      'Hemoglobin',
      'Potassium, Whole Blood',
      'WBC'
    )
),

lab_sd_per_admission AS (
  SELECT 
    hadm_id,
    STDDEV(valuenum) AS instability_score
  FROM lab_values
  GROUP BY hadm_id
  HAVING COUNT(valuenum) >= 2
),

instability_scores AS (
  SELECT 
    hadm_id,
    instability_score,
    PERCENTILE_CONT(instability_score, 0.9) OVER () AS p90_instability
  FROM lab_sd_per_admission
),

top_tier AS (
  SELECT 
    hadm_id,
    instability_score >= p90_instability AS is_top_tier
  FROM instability_scores
),

critical_flags AS (
  SELECT 
    c.hadm_id,
    lv.label,
    lv.valuenum,
    CASE 
      WHEN lv.label = 'Creatinine' AND lv.valuenum > 2.0 THEN 1
      WHEN lv.label = 'Potassium' AND (lv.valuenum < 3.0 OR lv.valuenum > 5.5) THEN 1
      WHEN lv.label = 'Platelet Count' AND lv.valuenum < 50 THEN 1
      WHEN lv.label = 'Hemoglobin' AND lv.valuenum < 7 THEN 1
      WHEN lv.label = 'Potassium, Whole Blood' AND (lv.valuenum < 3.0 OR lv.valuenum > 5.5) THEN 1
      WHEN lv.label = 'WBC' AND (lv.valuenum < 3.0 OR lv.valuenum > 15.0) THEN 1
      ELSE 0
    END AS is_critical,
    tt.is_top_tier
  FROM cohort c
  INNER JOIN lab_values lv ON c.hadm_id = lv.hadm_id
  LEFT JOIN top_tier tt ON c.hadm_id = tt.hadm_id
)

SELECT
  SUM(CASE WHEN is_top_tier THEN hospital_expire_flag ELSE 0 END) * 1.0 / COUNTIF(is_top_tier) AS top_tier_mortality,
  AVG(CASE WHEN is_top_tier THEN hospital_los_days END) AS top_tier_avg_los,
  SUM(CASE WHEN is_top_tier THEN is_critical ELSE 0 END) * 1.0 / COUNTIF(is_top_tier) AS top_tier_critical_rate,
  SUM(is_critical) * 1.0 / COUNT(*) AS all_cohort_critical_rate
FROM critical_flags cf
INNER JOIN cohort c ON cf.hadm_id = c.hadm_id;