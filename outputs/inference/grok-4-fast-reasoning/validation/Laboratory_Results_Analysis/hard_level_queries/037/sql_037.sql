WITH cohort_hadms AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 70 AND 80
    AND (
      (di.icd_version = 9 AND SUBSTR(CAST(di.icd_code AS STRING), 1, 3) IN ('430', '431', '432'))
      OR (di.icd_version = 10 AND SUBSTR(CAST(di.icd_code AS STRING), 1, 3) IN ('I60', 'I61', 'I62'))
    )
),
all_hadms AS (
  SELECT hadm_id, admittime 
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort_scores AS (
  SELECT 
    ch.hadm_id,
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' THEN le.itemid END) AS instability_score
  FROM cohort_hadms ch
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ch.hadm_id
    AND le.charttime >= ch.admittime
    AND le.charttime <= TIMESTAMP_ADD(ch.admittime, INTERVAL 48 HOUR)
  GROUP BY ch.hadm_id
),
all_scores AS (
  SELECT 
    ah.hadm_id,
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' THEN le.itemid END) AS instability_score
  FROM all_hadms ah
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ah.hadm_id
    AND le.charttime >= ah.admittime
    AND le.charttime <= TIMESTAMP_ADD(ah.admittime, INTERVAL 48 HOUR)
  GROUP BY ah.hadm_id
),
joined_cohort AS (
  SELECT 
    ch.*,
    COALESCE(cs.instability_score, 0) AS instability_score
  FROM cohort_hadms ch
  LEFT JOIN cohort_scores cs ON ch.hadm_id = cs.hadm_id
)
SELECT 
  p25_instability_score,
  cohort_critical_lab_event_rate,
  general_inpatient_critical_lab_event_rate,
  mean_los_days,
  in_hospital_mortality_rate
FROM (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.25) OVER() AS p25_instability_score,
    AVG(CASE WHEN instability_score > 0 THEN 1.0 ELSE 0.0 END) OVER() AS cohort_critical_lab_event_rate,
    AVG(los_days) OVER() AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) OVER() AS in_hospital_mortality_rate,
    (SELECT AVG(CASE WHEN COALESCE(instability_score, 0) > 0 THEN 1.0 ELSE 0.0 END) FROM all_scores) AS general_inpatient_critical_lab_event_rate
  FROM joined_cohort
)
LIMIT 1;