WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod,
    (SELECT COUNT(*) 
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
     WHERE di.hadm_id = a.hadm_id AND di.seq_num > 1) AS num_comorb,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 9 AND di.icd_code LIKE '584.%') 
             OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%'))
    ) AS has_aki,
    EXISTS(
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
        AND ((di.icd_version = 9 AND di.icd_code LIKE '518.5%') 
             OR (di.icd_version = 10 AND di.icd_code = 'J80'))
    ) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admission_type <> 'OBSERVATION'
    AND a.dischtime IS NOT NULL
),
filtered_cohort AS (
  SELECT *, 
    5 * num_comorb + IF(has_ards, 50, 0) AS risk_score
  FROM cohort 
  WHERE has_aki
),
quintiled AS (
  SELECT *, 
    NTILE(5) OVER (ORDER BY risk_score ASC) AS quintile
  FROM filtered_cohort
),
with_los AS (
  SELECT *, 
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los_days
  FROM quintiled
)
SELECT 
  quintile,
  COUNT(*) AS N,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN hospital_expire_flag = 0 
               AND dod IS NOT NULL 
               AND dod > CAST(dischtime AS DATE) 
               AND dod <= DATE_ADD(CAST(dischtime AS DATE), INTERVAL 30 DAY) 
           THEN 1 ELSE 0 END) * 100.0,
      SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END)
    ), 2
  ) AS mortality_30d_pct,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN has_ards THEN 1 ELSE 0 END) * 100.0,
      COUNT(*)
    ), 2
  ) AS ards_pct,
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 0 THEN los_days END, 
    2
  )[OFFSET(1)] AS median_survivor_los
FROM with_los
GROUP BY quintile
ORDER BY quintile;