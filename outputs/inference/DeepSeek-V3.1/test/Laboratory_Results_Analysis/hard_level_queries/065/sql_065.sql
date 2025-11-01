WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND diag.icd_code IN ('K922', 'K625', 'I8501', 'I8511')
    AND diag.icd_version = 10
    AND diag.seq_num = 1  -- primary diagnosis
),

cohort_labs AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  WHERE le.flag IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id
),

general_inpatients AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR)
  WHERE le.flag IS NOT NULL
  GROUP BY adm.subject_id, adm.hadm_id
)

SELECT 
  'GI Bleed Cohort' AS group_label,
  COUNT(*) AS num_patients,
  AVG(cl.critical_lab_count) AS avg_critical_labs,
  APPROX_QUANTILES(cl.critical_lab_count, 100)[OFFSET(25)] AS p25_critical_labs,
  AVG(c.los_days) AS avg_los_days,
  SUM(c.hospital_expire_flag) AS mortality_count,
  ROUND(SAFE_DIVIDE(SUM(c.hospital_expire_flag), COUNT(*)) * 100, 2) AS mortality_percent
FROM cohort c
LEFT JOIN cohort_labs cl
  ON c.hadm_id = cl.hadm_id

UNION ALL

SELECT 
  'General Inpatients' AS group_label,
  COUNT(*) AS num_patients,
  AVG(gi.critical_lab_count) AS avg_critical_labs,
  APPROX_QUANTILES(gi.critical_lab_count, 100)[OFFSET(25)] AS p25_critical_labs,
  NULL AS avg_los_days,
  NULL AS mortality_count,
  NULL AS mortality_percent
FROM general_inpatients gi;