WITH sepsis_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(long_title, r'(?i)sepsis')
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      INNER JOIN sepsis_codes sc
        ON diag.icd_code = sc.icd_code
        AND diag.icd_version = sc.icd_version
      WHERE
        diag.subject_id = a.subject_id
        AND diag.hadm_id = a.hadm_id
    )
),
filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE admission_age BETWEEN 43 AND 53
),
cohort_lab AS (
  SELECT
    fc.hadm_id,
    fc.los_days,
    fc.hospital_expire_flag,
    -- Count critical lab events (abnormal only) in first 72h
    COUNTIF(l.flag IS NOT NULL AND l.flag != 'normal') AS critical_lab_count
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON fc.subject_id = l.subject_id
    AND fc.hadm_id = l.hadm_id
    AND l.charttime >= fc.admittime
    AND l.charttime <= DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
  GROUP BY fc.hadm_id, fc.los_days, fc.hospital_expire_flag
)
SELECT
  COUNT(hadm_id) AS num_admissions,
  APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(25)] AS percentile_25_instability,
  AVG(critical_lab_count) AS mean_instability,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort_lab;