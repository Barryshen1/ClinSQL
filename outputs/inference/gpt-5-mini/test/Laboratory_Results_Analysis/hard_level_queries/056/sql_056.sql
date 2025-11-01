WITH cohort_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
       AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%asthma%'
    )
),

labs_48h AS (
  SELECT
    le.hadm_id,
    COUNT(1) AS total_labs_48h,
    SUM(CASE
          WHEN le.flag IS NOT NULL AND LOWER(le.flag) != 'normal' THEN 1
          WHEN le.valuenum IS NOT NULL AND (
                 (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
              OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
            ) THEN 1
          ELSE 0
        END) AS abnormal_labs_48h
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort_admissions ca
    ON le.hadm_id = ca.hadm_id
  WHERE le.charttime IS NOT NULL
    AND le.charttime >= ca.admittime
    AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
  GROUP BY le.hadm_id
),

per_admission AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    COALESCE(l.total_labs_48h, 0) AS total_labs_48h,
    COALESCE(l.abnormal_labs_48h, 0) AS abnormal_labs_48h,
    CASE
      WHEN COALESCE(l.total_labs_48h, 0) = 0 THEN 0.0
      ELSE SAFE_DIVIDE(COALESCE(l.abnormal_labs_48h, 0), l.total_labs_48h)
    END AS instability_score,
    SAFE_DIVIDE(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, MINUTE), 1440.0) AS los_days
  FROM cohort_admissions ca
  LEFT JOIN labs_48h l
    ON ca.hadm_id = l.hadm_id
),

p95 AS (
  SELECT
    (SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)]
     FROM per_admission) AS instability_p95
),

admission_with_flags AS (
  SELECT
    pa.*,
    p95.instability_p95,
    CASE WHEN pa.instability_score >= p95.instability_p95 THEN 1 ELSE 0 END AS is_top_5pct,
    SAFE_DIVIDE(pa.abnormal_labs_48h, GREATEST(pa.los_days, 1.0/24.0)) AS abnormal_labs_per_hosp_day
  FROM per_admission pa
  CROSS JOIN p95
)

SELECT
  CASE WHEN is_top_5pct = 1 THEN 'top_5pct' ELSE 'rest_of_cohort' END AS grp,
  COUNT(1) AS n_admissions,
  ROUND(AVG(los_days), 3) AS mean_los_days,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS approx_median_los_days,
  ROUND(SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)), 4) AS hospital_mortality_rate,
  ROUND(AVG(abnormal_labs_per_hosp_day), 3) AS mean_abnormal_labs_per_hosp_day,
  ROUND(AVG(instability_score), 4) AS mean_instability_score,
  ROUND(MIN(instability_score), 4) AS min_instability_score,
  ROUND(MAX(instability_score), 4) AS max_instability_score,
  ROUND((SELECT instability_p95 FROM p95), 4) AS cohort_instability_p95
FROM admission_with_flags
GROUP BY grp
ORDER BY grp DESC;