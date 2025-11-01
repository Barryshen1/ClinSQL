WITH
-- Base admissions for female patients age 50-60
base_adm AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    LOWER(p.gender) IN ('female','f')
    AND p.anchor_age BETWEEN 50 AND 60
),

-- Admissions with a diagnosis that mentions "hyperosmolar" in ICD description (captures HHS ICD9/10 textual matches)
hhs_adm AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  USING(icd_code, icd_version)
  WHERE
    LOWER(dd.long_title) LIKE '%hyperosmolar%'
),

-- HHS cohort: female age 50-60 admissions that have HHS diagnosis
cohort_hhs AS (
  SELECT
    b.*
  FROM
    base_adm b
  JOIN
    hhs_adm h
  USING(hadm_id)
),

-- Abnormal lab events in first 48 hours for the HHS cohort
hhs_labevents_abnormal AS (
  SELECT
    le.hadm_id,
    le.itemid,
    -- define abnormal if numeric value is out of provided ref range OR flag indicates abnormal
    (CASE
       WHEN le.valuenum IS NOT NULL
            AND (
              (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
              OR
              (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
            )
         THEN 1
       WHEN le.flag IS NOT NULL AND LOWER(le.flag) NOT IN ('normal','nl','n','')
         THEN 1
       ELSE 0
     END) AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    cohort_hhs c
  ON
    le.hadm_id = c.hadm_id
  WHERE
    le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
),

-- Instability score per HHS admission (count distinct abnormal itemids)
hhs_instability AS (
  SELECT
    c.hadm_id,
    COALESCE(s.instability_score, 0) AS instability_score,
    COALESCE(s.any_abnormal, FALSE) AS any_abnormal,
    c.hospital_expire_flag,
    c.admittime,
    c.dischtime
  FROM
    cohort_hhs c
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS instability_score,
      COUNTIF(is_abnormal = 1) > 0 AS any_abnormal
    FROM
      hhs_labevents_abnormal
    GROUP BY
      hadm_id
  ) s
  USING(hadm_id)
),

-- Compute the 75th percentile among HHS cohort instability scores
hhs_p75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
  FROM
    hhs_instability
),

-- Now compute lab abnormality for all female 50-60 admissions for comparison (general inpatients)
all_labevents_abnormal AS (
  SELECT
    le.hadm_id,
    le.itemid,
    (CASE
       WHEN le.valuenum IS NOT NULL
            AND (
              (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
              OR
              (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
            )
         THEN 1
       WHEN le.flag IS NOT NULL AND LOWER(le.flag) NOT IN ('normal','nl','n','')
         THEN 1
       ELSE 0
     END) AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    base_adm b
  ON
    le.hadm_id = b.hadm_id
  WHERE
    le.charttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 48 HOUR)
),

all_instability AS (
  SELECT
    b.hadm_id,
    COALESCE(s.instability_score, 0) AS instability_score,
    COALESCE(s.any_abnormal, FALSE) AS any_abnormal,
    b.hospital_expire_flag,
    b.admittime,
    b.dischtime
  FROM
    base_adm b
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT CASE WHEN is_abnormal = 1 THEN itemid END) AS instability_score,
      COUNTIF(is_abnormal = 1) > 0 AS any_abnormal
    FROM
      all_labevents_abnormal
    GROUP BY hadm_id
  ) s
  USING(hadm_id)
)

-- Final aggregates: report p75, HHS metrics for admissions >= p75, and critical-lab rates for HHS>=p75 vs general female 50-60 inpatients
SELECT
  (SELECT p75 FROM hhs_p75) AS instability_score_p75,
  -- HHS subgroup metrics (instability_score >= p75)
  hhs_metrics.hhs_count,
  hhs_metrics.hhs_mortality_rate,
  hhs_metrics.hhs_mean_los_days,
  hhs_metrics.hhs_critical_lab_rate AS hhs_critical_lab_rate,
  -- General inpatients metrics for comparison
  general_metrics.general_count,
  general_metrics.general_critical_lab_rate
FROM
  -- compute HHS metrics
  (
    SELECT
      COUNT(*) AS hhs_count,
      SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS hhs_mortality_rate,
      AVG(SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400)) AS hhs_mean_los_days,
      SAFE_DIVIDE(SUM(CASE WHEN any_abnormal THEN 1 ELSE 0 END), COUNT(*)) AS hhs_critical_lab_rate
    FROM
      hhs_instability,
      hhs_p75
    WHERE
      instability_score >= hhs_p75.p75
  ) AS hhs_metrics,
  -- compute general inpatient critical-lab rate among all female 50-60 admissions
  (
    SELECT
      COUNT(*) AS general_count,
      SAFE_DIVIDE(SUM(CASE WHEN any_abnormal THEN 1 ELSE 0 END), COUNT(*)) AS general_critical_lab_rate
    FROM
      all_instability
  ) AS general_metrics;