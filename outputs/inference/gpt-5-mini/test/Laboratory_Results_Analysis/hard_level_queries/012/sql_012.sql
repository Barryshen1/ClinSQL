WITH
-- Identify admissions with an AMI diagnosis by matching d_icd_diagnoses.long_title
ami_hadm AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON dic.icd_code = di.icd_code
   AND dic.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND LOWER(dic.long_title) LIKE '%myocardial infarction%'
),

-- All eligible general admissions (same age/gender window) for comparison
general_hadm AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Per-admission abnormal lab counts in first 72 hours (for any admission list we supply)
per_admission_abn AS (
  -- AMI admissions
  SELECT
    'AMI' AS cohort,
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    -- compute LOS in days as fractional days
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days,
    COALESCE(SUM(
      CASE
        WHEN le.flag = 'abnormal' THEN 1
        WHEN le.valuenum IS NOT NULL
             AND ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                  OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
             THEN 1
        ELSE 0
      END
    ), 0) AS abnormal_count,
    CASE
      WHEN COALESCE(SUM(
        CASE
          WHEN le.flag = 'abnormal' THEN 1
          WHEN le.valuenum IS NOT NULL
               AND ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                    OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
               THEN 1
          ELSE 0
        END
      ), 0) > 0 THEN 1 ELSE 0 END AS has_abnormal
  FROM ami_hadm h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = h.hadm_id
   AND le.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY 1,2,3,4,5,6,7

  UNION ALL

  -- General admissions
  SELECT
    'General' AS cohort,
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    h.hospital_expire_flag,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, SECOND) / 86400.0 AS los_days,
    COALESCE(SUM(
      CASE
        WHEN le.flag = 'abnormal' THEN 1
        WHEN le.valuenum IS NOT NULL
             AND ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                  OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
             THEN 1
        ELSE 0
      END
    ), 0) AS abnormal_count,
    CASE
      WHEN COALESCE(SUM(
        CASE
          WHEN le.flag = 'abnormal' THEN 1
          WHEN le.valuenum IS NOT NULL
               AND ((le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                    OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper))
               THEN 1
          ELSE 0
        END
      ), 0) > 0 THEN 1 ELSE 0 END AS has_abnormal
  FROM general_hadm h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = h.hadm_id
   AND le.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
  GROUP BY 1,2,3,4,5,6,7
),

-- Aggregate cohort-level metrics
cohort_metrics AS (
  SELECT
    cohort,
    COUNT(*) AS n_admissions,
    -- 75th percentile of first-72h abnormal-count instability score
    APPROX_QUANTILES(abnormal_count, 100)[OFFSET(75)] AS pct75_instability_count,
    -- mean abnormal events per admission
    AVG(abnormal_count) AS mean_abnormal_per_admission,
    -- percent admissions with >=1 abnormal lab in first 72h
    100.0 * SUM(CASE WHEN abnormal_count > 0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_admissions_with_abnormal,
    -- LOS metrics
    AVG(los_days) AS mean_los_days,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
    -- in-hospital mortality (hospital_expire_flag: 1 = died in hospital)
    100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS pct_inhospital_mortality
  FROM per_admission_abn
  GROUP BY cohort
)

SELECT * FROM cohort_metrics
ORDER BY cohort;