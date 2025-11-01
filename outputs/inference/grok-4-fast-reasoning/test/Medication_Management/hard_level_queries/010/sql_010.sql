WITH cohort AS (
  SELECT a.*, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
),
scores AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT pres.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON pres.hadm_id = c.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
  GROUP BY c.hadm_id
),
cohort_with_scores AS (
  SELECT 
    c.*,
    COALESCE(s.complexity_score, 0) AS complexity_score
  FROM cohort c
  LEFT JOIN scores s
    ON c.hadm_id = s.hadm_id
),
with_readmit AS (
  SELECT 
    c.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.hadm_id != c.hadm_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS has_readmission
  FROM cohort_with_scores c
),
cohort_final AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY complexity_score) AS quintile
  FROM with_readmit
)
SELECT 
  quintile,
  COUNT(*) AS num_patients,
  AVG(complexity_score) AS mean_complexity_score,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate,
  SUM(IF(has_readmission, 1, 0)) / COUNT(*) AS readmission_rate_30d
FROM cohort_final
GROUP BY quintile
ORDER BY quintile;