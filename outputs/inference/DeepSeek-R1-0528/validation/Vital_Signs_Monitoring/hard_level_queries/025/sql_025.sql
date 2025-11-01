WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ie.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year BETWEEN 55 AND 65)
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '427.41') 
      OR (diag.icd_version = 10 AND diag.icd_code IN ('I46.2', 'I46.8', 'I46.9'))
    )
),

vitals AS (
  SELECT 
    c.stay_id,
    CASE WHEN c.itemid IN (220045, 211) THEN c.valuenum END AS heart_rate,
    CASE WHEN c.itemid IN (220179, 51, 442, 455, 6701, 220050, 220051) THEN c.valuenum END AS systolic_bp,
    CASE WHEN c.itemid IN (220210, 618, 615, 224690, 224689) THEN c.valuenum END AS resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN cohort co
    ON c.stay_id = co.stay_id
  WHERE c.charttime >= co.intime
    AND c.charttime < DATETIME_ADD(co.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
),

vitals_agg AS (
  SELECT 
    stay_id,
    STDDEV(heart_rate) AS hr_std,
    STDDEV(systolic_bp) AS sbp_std,
    STDDEV(resp_rate) AS resp_std
  FROM vitals
  GROUP BY stay_id
),

score_computation AS (
  SELECT 
    stay_id,
    COALESCE(hr_std, 100) * 100 + COALESCE(sbp_std, 100) * 10 + COALESCE(resp_std, 100) * 100 AS score
  FROM vitals_agg
),

cohort_with_score AS (
  SELECT 
    co.*,
    COALESCE(sc.score, 0) AS score
  FROM cohort co
  LEFT JOIN score_computation sc
    ON co.stay_id = sc.stay_id
),

unstable_decile AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY score DESC) AS decile
  FROM cohort_with_score
)

SELECT
  SAFE_DIVIDE(
    (SELECT COUNTIF(score <= 70) FROM cohort_with_score),
    (SELECT COUNT(*) FROM cohort_with_score)
  ) * 100 AS percentile_70,
  (SELECT AVG(los) FROM unstable_decile WHERE decile = 1) AS mean_los_top_decile,
  (SELECT AVG(hospital_expire_flag) FROM unstable_decile WHERE decile = 1) AS mortality_rate_top_decile;