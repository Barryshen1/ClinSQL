WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime, 
    ie.outtime,
    ie.los,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) AS age_at_icu_admit,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 85 AND 95
    AND ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code = '51881') 
        OR (icd_version = 10 AND icd_code LIKE 'J96%')
    )
),

vital_items AS (
  SELECT 220045 AS itemid, 'HR' AS vital, 60.0 AS low, 100.0 AS high UNION ALL
  SELECT 220179, 'SBP', 90.0, 140.0 UNION ALL
  SELECT 220180, 'DBP', 60.0, 90.0 UNION ALL
  SELECT 220181, 'MAP', 60.0, 100.0 UNION ALL
  SELECT 220210, 'RR', 12.0, 20.0 UNION ALL
  SELECT 223762, 'Temp', 36.0, 37.5 UNION ALL
  SELECT 223761, 'Temp', 36.0, 37.5 UNION ALL
  SELECT 220277, 'SpO2', 95.0, NULL
),

vital_events AS (
  SELECT 
    c.stay_id,
    ce.itemid,
    CASE 
      WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9
      ELSE ce.valuenum
    END AS valuenum,
    vi.vital,
    vi.low,
    vi.high
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  INNER JOIN vital_items vi
    ON ce.itemid = vi.itemid
  WHERE ce.valuenum IS NOT NULL
),

abnormal_events AS (
  SELECT 
    stay_id,
    CASE 
      WHEN vital = 'SpO2' AND valuenum < low THEN 1
      WHEN vital != 'SpO2' AND (valuenum < low OR valuenum > high) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM vital_events
),

instability_scores AS (
  SELECT 
    stay_id,
    SUM(is_abnormal) AS instability_score
  FROM abnormal_events
  GROUP BY stay_id
),

cohort_with_score AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COALESCE(i.instability_score, 0) AS instability_score
  FROM cohort c
  LEFT JOIN instability_scores i
    ON c.stay_id = i.stay_id
),

percentile_rank AS (
  SELECT 
    ROUND(SAFE_DIVIDE(COUNTIF(instability_score <= 85), COUNT(*)) * 100, 2) AS percentile_rank_85
  FROM cohort_with_score
),

quartile_cutoff AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS q75
  FROM cohort_with_score
),

most_unstable AS (
  SELECT 
    c.stay_id,
    c.los,
    c.hospital_expire_flag
  FROM cohort_with_score c
  CROSS JOIN quartile_cutoff q
  WHERE c.instability_score >= q.q75
)

SELECT 
  (SELECT percentile_rank_85 FROM percentile_rank) AS percentile_rank_85,
  ROUND(AVG(los), 2) AS avg_icu_los_quartile,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_percent_quartile
FROM most_unstable;