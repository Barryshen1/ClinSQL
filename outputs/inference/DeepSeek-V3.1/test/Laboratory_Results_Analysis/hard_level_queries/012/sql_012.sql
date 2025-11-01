WITH
  -- All inpatients for lab reference ranges
  all_inpatients AS (
    SELECT DISTINCT p.subject_id, p.gender, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE a.admission_type LIKE '%INPATIENT%'
      AND p.anchor_age BETWEEN 44 AND 54
  ),
  -- AMI cohort: male inpatients aged 44-54 with AMI
  ami_cohort AS (
    SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime,
           a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.hadm_id = di.hadm_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 44 AND 54
      AND di.icd_code LIKE 'I21%'
      AND di.icd_version = 10
      AND a.admission_type LIKE '%INPATIENT%'
  ),
  -- Lab medians and IQRs from all inpatients (44-54)
  lab_stats AS (
    SELECT
      le.itemid,
      APPROX_QUANTILES(le.valuenum, 100) [OFFSET(50)] AS median,
      APPROX_QUANTILES(le.valuenum, 100) [OFFSET(75)] AS q3,
      APPROX_QUANTILES(le.valuenum, 100) [OFFSET(25)] AS q1,
      APPROX_QUANTILES(le.valuenum, 100) [OFFSET(75)] - APPROX_QUANTILES(le.valuenum, 100) [OFFSET(25)] AS iqr
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN all_inpatients ip
      ON le.subject_id = ip.subject_id
    WHERE le.valuenum IS NOT NULL
    GROUP BY le.itemid
  ),
  -- Lab events for AMI cohort in first 72 hours
  ami_labs AS (
    SELECT
      ac.subject_id,
      ac.hadm_id,
      le.itemid,
      le.valuenum,
      ls.median,
      ls.iqr,
      -- Instability score for each lab
      ABS(le.valuenum - ls.median) / NULLIF(ls.iqr, 0) AS instability
    FROM ami_cohort ac
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ac.hadm_id = le.hadm_id
    INNER JOIN lab_stats ls
      ON le.itemid = ls.itemid
    WHERE le.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 72 HOUR)
      AND le.valuenum IS NOT NULL
  ),
  -- Max instability per AMI patient
  ami_max_instability AS (
    SELECT
      subject_id,
      MAX(instability) AS max_instability
    FROM ami_labs
    GROUP BY subject_id
  ),
  -- Critical labs for AMI cohort (beyond 3*IQR)
  ami_critical_labs AS (
    SELECT
      subject_id,
      COUNT(*) AS critical_count
    FROM ami_labs
    WHERE instability > 3
    GROUP BY subject_id
  ),
  -- Lab events for all inpatients (comparison) in first 72 hours
  all_ip_labs AS (
    SELECT
      ip.subject_id,
      a.hadm_id,
      le.itemid,
      le.valuenum,
      ls.median,
      ls.iqr,
      ABS(le.valuenum - ls.median) / NULLIF(ls.iqr, 0) AS instability
    FROM all_inpatients ip
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON ip.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
    INNER JOIN lab_stats ls
      ON le.itemid = ls.itemid
    WHERE le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      AND le.valuenum IS NOT NULL
  ),
  -- Critical labs for all inpatients
  all_ip_critical_labs AS (
    SELECT
      subject_id,
      COUNT(*) AS critical_count
    FROM all_ip_labs
    WHERE instability > 3
    GROUP BY subject_id
  )

-- Final output
SELECT
  (SELECT
      APPROX_QUANTILES(max_instability, 100)[OFFSET(75)]
      FROM ami_max_instability) AS percentile_75_max_instability,

  (SELECT
      AVG(critical_count)
      FROM ami_critical_labs) AS ami_avg_critical_labs_per_patient,

  (SELECT
      AVG(critical_count)
      FROM all_ip_critical_labs) AS all_ip_avg_critical_labs_per_patient,

  (SELECT
      AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0)
      FROM ami_cohort) AS avg_los_days,

  (SELECT
      AVG(hospital_expire_flag)
      FROM ami_cohort) AS mortality_rate;