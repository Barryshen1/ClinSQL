WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%'))
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),
first72_labs AS (
  SELECT
    le.hadm_id,
    di.category,
    le.flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON le.itemid = di.itemid
  INNER JOIN cohort c
    ON le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
    AND le.valuenum IS NOT NULL
    AND di.category IS NOT NULL
),
scores AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT category) AS lab_instability_score,
    COUNT(*) AS num_critical_labs
  FROM first72_labs
  GROUP BY hadm_id
),
full_cohort AS (
  SELECT
    c.*,
    COALESCE(s.lab_instability_score, 0) AS score,
    COALESCE(s.num_critical_labs, 0) AS num_crit_labs
  FROM cohort c
  LEFT JOIN scores s
    ON c.hadm_id = s.hadm_id
),
p90 AS (
  SELECT APPROX_QUANTILES(score, 100)[OFFSET(90)] AS p90_score
  FROM full_cohort
),
augmented AS (
  SELECT
    fc.*,
    p90.p90_score,
    CASE
      WHEN fc.score >= p90.p90_score THEN 'high'
      ELSE 'low'
    END AS group_flag
  FROM full_cohort fc
  CROSS JOIN p90
)
SELECT
  group_flag,
  p90_score,
  COUNT(*) AS num_patients,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0), 2) AS mean_los_days,
  ROUND(AVG(num_crit_labs), 2) AS avg_critical_labs_per_patient
FROM augmented
GROUP BY group_flag, p90_score
ORDER BY
  CASE WHEN group_flag = 'high' THEN 1 ELSE 2 END;