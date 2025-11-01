WITH
-- 1) Female admissions aged 90-100 with AMI diagnosis
female_ami_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    -- require at least one AMI diagnosis on this admission
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '410'))
          OR (d.icd_version = 10 AND (STARTS_WITH(d.icd_code, 'I21') OR STARTS_WITH(d.icd_code, 'I22')))
        )
    )
),

-- 2) Aggregate abnormal lab events within first 48 hours for female AMI admissions
female_ami_lab_agg AS (
  SELECT
    fa.hadm_id,
    fa.admittime,
    SUM(CASE
            WHEN (
              -- flag indicates abnormal/high/low (case-insensitive)
              (l.flag IS NOT NULL AND (
                LOWER(l.flag) LIKE '%abnorm%' OR LOWER(l.flag) IN ('h','high','l','low','abnormal')
              ))
              -- or numeric value outside reference ranges when ref bounds present
              OR (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
              OR (l.valuenum IS NOT NULL AND l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
            ) THEN 1 ELSE 0 END) AS abnormal_event_count,
    COUNT(l.labevent_id) AS total_lab_events
  FROM
    female_ami_adms fa
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = fa.hadm_id
       AND l.charttime >= fa.admittime
       AND l.charttime < TIMESTAMP_ADD(fa.admittime, INTERVAL 48 HOUR)
  GROUP BY
    fa.hadm_id, fa.admittime
),

-- 3) Per-admission lab-instability scores for female AMI admissions (include zeros)
female_ami_scores AS (
  SELECT
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.hospital_expire_flag,
    COALESCE(fala.abnormal_event_count, 0) AS lab_instability_score,
    CASE WHEN COALESCE(fala.abnormal_event_count, 0) > 0 THEN 1 ELSE 0 END AS any_abnormal_lab,
    SAFE_DIVIDE(TIMESTAMP_DIFF(fa.dischtime, fa.admittime, SECOND), 86400.0) AS los_days
  FROM
    female_ami_adms fa
  LEFT JOIN
    female_ami_lab_agg fala
    USING(hadm_id)
),

-- 4) Compute approximate P75 for lab_instability_score among female AMI admissions
p75_val AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_score
  FROM
    female_ami_scores
),

-- 5) All inpatients aged 90-100 (any sex) baseline group
all90_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.anchor_age BETWEEN 90 AND 100
),

-- 6) Aggregate abnormal lab events within first 48 hours for all inpatients 90-100
all90_lab_agg AS (
  SELECT
    a.hadm_id,
    SUM(CASE
            WHEN (
              (l.flag IS NOT NULL AND (
                LOWER(l.flag) LIKE '%abnorm%' OR LOWER(l.flag) IN ('h','high','l','low','abnormal')
              ))
              OR (l.valuenum IS NOT NULL AND l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
              OR (l.valuenum IS NOT NULL AND l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
            ) THEN 1 ELSE 0 END) AS abnormal_event_count,
    COUNT(l.labevent_id) AS total_lab_events
  FROM
    all90_adms a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = a.hadm_id
       AND l.charttime >= a.admittime
       AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.hadm_id
),

-- 7) Per-admission lab-instability scores for all 90-100 inpatients
all90_scores AS (
  SELECT
    a.hadm_id,
    COALESCE(alla.abnormal_event_count, 0) AS lab_instability_score,
    CASE WHEN COALESCE(alla.abnormal_event_count, 0) > 0 THEN 1 ELSE 0 END AS any_abnormal_lab,
    a.hospital_expire_flag,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM
    all90_adms a
  LEFT JOIN
    all90_lab_agg alla
    USING(hadm_id)
)

-- Final report: metrics for 1) female AMI admissions with score >= P75 and 2) all inpatients 90-100
SELECT
  cohort_label,
  n_admissions,
  ROUND(100 * mortality_rate, 2) AS pct_in_hospital_mortality,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(100 * critical_lab_rate, 2) AS pct_with_any_critical_lab_first_48h,
  ROUND(mean_lab_instability_score, 2) AS mean_lab_instability_score
FROM (
  -- A: female AMI admissions with lab_instability_score >= P75
  SELECT
    'Female AMI, age 90-100, >= P75 lab-instability' AS cohort_label,
    COUNT(*) AS n_admissions,
    AVG(CAST(s.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(s.los_days) AS mean_los_days,
    AVG(CAST(s.any_abnormal_lab AS FLOAT64)) AS critical_lab_rate,
    AVG(s.lab_instability_score) AS mean_lab_instability_score
  FROM
    female_ami_scores s,
    p75_val
  WHERE
    s.lab_instability_score >= p75_val.p75_score

  UNION ALL

  -- B: all inpatients age 90-100 (baseline comparator)
  SELECT
    'All inpatients, age 90-100 (all diagnoses/sexes)' AS cohort_label,
    COUNT(*) AS n_admissions,
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(a.los_days) AS mean_los_days,
    AVG(CAST(a.any_abnormal_lab AS FLOAT64)) AS critical_lab_rate,
    AVG(a.lab_instability_score) AS mean_lab_instability_score
  FROM
    all90_scores a
)
ORDER BY cohort_label;