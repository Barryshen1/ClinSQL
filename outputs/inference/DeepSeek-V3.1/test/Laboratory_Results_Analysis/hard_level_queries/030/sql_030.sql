WITH asthma_cohort AS (
  SELECT DISTINCT
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
    -- Calculate actual age at admission
    DATETIME_DIFF(adm.admittime, 
                  DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), 
                  YEAR) + pat.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J45%') OR
      (diag.icd_version = 9 AND diag.icd_code LIKE '493%')
    )
    -- Filter by calculated age at admission
    AND DATETIME_DIFF(adm.admittime, 
                      DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), 
                      YEAR) + pat.anchor_age BETWEEN 39 AND 49
),

cohort_lab_events AS (
  SELECT 
    ac.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM asthma_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ac.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 48 HOUR)
  WHERE le.flag = 'abnormal'
  GROUP BY ac.hadm_id
),

all_admissions_lab_events AS (
  SELECT 
    adm.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 48 HOUR)
  WHERE le.flag = 'abnormal'
  GROUP BY adm.hadm_id
)

SELECT 
  (SELECT APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(75)]
   FROM cohort_lab_events) AS percentile_75_lab_instability_score,

  (SELECT AVG(critical_lab_count) 
   FROM cohort_lab_events) AS avg_lab_instability_cohort,

  (SELECT AVG(critical_lab_count) 
   FROM all_admissions_lab_events) AS avg_lab_instability_all,

  (SELECT AVG(los_days) 
   FROM asthma_cohort) AS avg_los_days_cohort,

  (SELECT AVG(CAST(hospital_expire_flag AS INT)) * 100 
   FROM asthma_cohort) AS in_hospital_mortality_percent_cohort;