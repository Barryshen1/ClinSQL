WITH female_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

stroke_dx AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN di.icd_code LIKE 'I63%' THEN 1 ELSE 0 END) AS has_ischemic,
    MAX(CASE WHEN di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' THEN 1 ELSE 0 END) AS has_hemorrh
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE
    di.icd_version = 10
  GROUP BY
    di.subject_id,
    di.hadm_id
),

stroke_cohort AS (
  SELECT
    f.*,
    CASE
      WHEN s.has_ischemic = 1 AND s.has_hemorrh = 0 THEN 'Ischemic'
      WHEN s.has_hemorrh = 1 AND s.has_ischemic = 0 THEN 'Hemorrhagic'
      ELSE NULL
    END AS stroke_type
  FROM
    female_adm f
    JOIN stroke_dx s
      USING(subject_id, hadm_id)
  WHERE
    (s.has_ischemic + s.has_hemorrh) = 1
),

comorbidity AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.stroke_type,
    TIMESTAMP_DIFF(sc.dischtime, sc.admittime, DAY) AS los_days,
    sc.hospital_expire_flag,
    -- count comorbidities excluding stroke codes
    COUNT(DISTINCT CASE 
      WHEN di.icd_version = 10
        AND di.icd_code NOT LIKE 'I63%'
        AND di.icd_code NOT LIKE 'I60%'
        AND di.icd_code NOT LIKE 'I61%'
      THEN di.icd_code
      ELSE NULL END) AS comorb_count,
    -- CKD flag
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Diabetes flag
    MAX(CASE WHEN di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%') THEN 1 ELSE 0 END) AS has_dm
  FROM
    stroke_cohort sc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      USING(subject_id, hadm_id)
  GROUP BY
    sc.subject_id,
    sc.hadm_id,
    sc.stroke_type,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag
),

with_tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (PARTITION BY stroke_type ORDER BY comorb_count) AS comorb_tertile
  FROM
    comorbidity
)

SELECT
  stroke_type,
  comorb_tertile,
  -- In-hospital mortality %
  100.0 * AVG(hospital_expire_flag) AS pct_mortality,
  -- Median LOS
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
  -- % LOS < 8 days
  100.0 * AVG(CASE WHEN los_days < 8 THEN 1 ELSE 0 END) AS pct_los_lt_8,
  -- % LOS ≥ 8 days
  100.0 * AVG(CASE WHEN los_days >= 8 THEN 1 ELSE 0 END) AS pct_los_ge_8,
  -- % with CKD
  100.0 * AVG(has_ckd) AS pct_ckd,
  -- % with diabetes
  100.0 * AVG(has_dm) AS pct_diabetes
FROM
  with_tertiles
GROUP BY
  stroke_type,
  comorb_tertile
ORDER BY
  stroke_type,
  comorb_tertile;