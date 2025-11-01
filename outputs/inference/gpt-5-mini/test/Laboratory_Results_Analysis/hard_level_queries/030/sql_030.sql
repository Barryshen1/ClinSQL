WITH
-- admissions with computed LOS in days
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- identify admissions that have any asthma-related diagnosis (ICD mapped via d_icd_diagnoses)
asthma_hadm AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code
   AND d.icd_version = dic.icd_version
  WHERE LOWER(dic.long_title) LIKE '%asthma%'
),

-- critical lab events counted per admission within first 48 hours of admission
lab_critical_counts AS (
  SELECT
    a.hadm_id,
    SUM(CASE
          WHEN (
                -- numeric outside reference range when ref bounds exist
                l.valuenum IS NOT NULL
                AND (
                     (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
                  OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
                )
               )
             OR -- OR flag contains 'crit' or 'abn' (catch 'critical' and 'abnormal' variants)
               (LOWER(COALESCE(l.flag, '')) LIKE '%crit%')
             OR (LOWER(COALESCE(l.flag, '')) LIKE '%abn%')
          THEN 1 ELSE 0 END) AS critical_lab_events_first48,
    COUNT(*) AS total_lab_events_first48
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id
),

-- per-admission table (all admissions) with coalesced critical event counts and LOS
per_admission AS (
  SELECT
    awl.subject_id,
    awl.hadm_id,
    awl.admittime,
    awl.dischtime,
    awl.hospital_expire_flag,
    awl.los_days,
    COALESCE(lcc.critical_lab_events_first48, 0) AS critical_lab_events_first48
  FROM admissions_with_los awl
  LEFT JOIN lab_critical_counts lcc
    ON awl.hadm_id = lcc.hadm_id
),

-- cohort: female, age 39-49, and admission has an asthma diagnosis
cohort_admissions AS (
  SELECT DISTINCT pa.*
  FROM per_admission pa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pa.subject_id = p.subject_id
  JOIN asthma_hadm ah
    ON pa.hadm_id = ah.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
)

-- Final aggregates comparing cohort vs all inpatients
SELECT
  -- Cohort-level counts & event statistics
  (SELECT COUNT(*) FROM cohort_admissions) AS cohort_n_admissions,
  (SELECT ROUND(AVG(critical_lab_events_first48), 3) FROM cohort_admissions) AS cohort_mean_events_per_admission,
  (SELECT APPROX_QUANTILES(critical_lab_events_first48, 2)[OFFSET(1)] FROM cohort_admissions) AS cohort_median_events_per_admission_approx,
  (SELECT APPROX_QUANTILES(critical_lab_events_first48, 100)[OFFSET(75)] FROM cohort_admissions) AS cohort_75th_percentile_events_per_admission_approx,
  -- Cohort LOS & mortality
  (SELECT ROUND(AVG(los_days), 3) FROM cohort_admissions) AS cohort_mean_los_days,
  (SELECT APPROX_QUANTILES(los_days, 2)[OFFSET(1)] FROM cohort_admissions) AS cohort_median_los_days_approx,
  (SELECT ROUND(SUM(hospital_expire_flag) / COUNT(*), 4) FROM cohort_admissions) AS cohort_inhospital_mortality_rate,
  -- All inpatients: counts & event statistics for comparison
  (SELECT COUNT(*) FROM per_admission) AS all_n_admissions,
  (SELECT ROUND(AVG(critical_lab_events_first48), 3) FROM per_admission) AS all_mean_events_per_admission,
  (SELECT APPROX_QUANTILES(critical_lab_events_first48, 2)[OFFSET(1)] FROM per_admission) AS all_median_events_per_admission_approx,
  (SELECT APPROX_QUANTILES(critical_lab_events_first48, 100)[OFFSET(75)] FROM per_admission) AS all_75th_percentile_events_per_admission_approx
;