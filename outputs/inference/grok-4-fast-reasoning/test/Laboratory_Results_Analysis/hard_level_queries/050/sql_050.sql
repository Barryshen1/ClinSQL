WITH subjects AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 40 AND 50
),
admissions AS (
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN subjects s ON a.subject_id = s.subject_id
),
ards_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  INNER JOIN admissions USING (hadm_id)
  WHERE ((icd_version = 10 AND icd_code = 'J80') OR (icd_version = 9 AND icd_code = '51882'))
),
non_ards_hadms AS (
  SELECT a.hadm_id
  FROM admissions a
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE ((icd_version = 10 AND icd_code = 'J80') OR (icd_version = 9 AND icd_code = '51882'))
  ) ards ON a.hadm_id = ards.hadm_id
  WHERE ards.hadm_id IS NULL
),
scores_ards AS (
  SELECT 
    ah.hadm_id,
    SUM(CASE 
      WHEN l.charttime >= a.admittime 
        AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) 
        AND l.flag IS NOT NULL 
      THEN 1 
      ELSE 0 
    END) AS instability_score
  FROM ards_hadms ah
  INNER JOIN admissions a ON ah.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON l.hadm_id = ah.hadm_id
  GROUP BY ah.hadm_id
),
scores_non AS (
  SELECT 
    nh.hadm_id,
    SUM(CASE 
      WHEN l.charttime >= a.admittime 
        AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR) 
        AND l.flag IS NOT NULL 
      THEN 1 
      ELSE 0 
    END) AS instability_score
  FROM non_ards_hadms nh
  INNER JOIN admissions a ON nh.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON l.hadm_id = nh.hadm_id
  GROUP BY nh.hadm_id
),
p75_cte AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS threshold
  FROM scores_ards
),
high_group AS (
  SELECT 
    sa.hadm_id,
    sa.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM scores_ards sa
  INNER JOIN admissions a ON sa.hadm_id = a.hadm_id
  CROSS JOIN p75_cte p
  WHERE sa.instability_score >= p.threshold
)
SELECT 
  (SELECT threshold FROM p75_cte) AS p75_instability_score,
  (SELECT AVG(hospital_expire_flag) FROM high_group) AS mortality_rate,
  (SELECT AVG(los_days) FROM high_group) AS mean_los_days,
  (SELECT AVG(instability_score) FROM high_group) AS avg_critical_events_high_group,
  (SELECT AVG(instability_score) FROM scores_non) AS avg_critical_events_non_ards;