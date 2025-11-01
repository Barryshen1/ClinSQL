WITH cardiac_arrest_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code = '4275') 
        OR (icd_version = 10 AND icd_code IN ('I46.2', 'I46.8', 'I46.9'))
    )
),

control_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND adm.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code = '4275') 
        OR (icd_version = 10 AND icd_code IN ('I46.2', 'I46.8', 'I46.9'))
    )
),

cardiac_lab_events AS (
  SELECT 
    c.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM cardiac_arrest_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL  -- Abnormal result
  GROUP BY c.hadm_id
),

control_lab_events AS (
  SELECT 
    c.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM control_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY c.hadm_id
),

cardiac_summary AS (
  SELECT 
    'Cardiac Arrest' AS cohort,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(1)] AS instab_score_q1,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(2)] AS instab_score_median,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(3)] AS instab_score_q3,
    APPROX_QUANTILES(c.los_days, 4)[OFFSET(1)] AS los_q1,
    APPROX_QUANTILES(c.los_days, 4)[OFFSET(2)] AS los_median,
    APPROX_QUANTILES(c.los_days, 4)[OFFSET(3)] AS los_q3,
    SUM(c.hospital_expire_flag) AS mortality_count,
    COUNT(*) AS total_patients,
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_percent
  FROM cardiac_arrest_cohort c
  INNER JOIN cardiac_lab_events cl
    ON c.hadm_id = cl.hadm_id
),

control_summary AS (
  SELECT 
    'Control' AS cohort,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(1)] AS instab_score_q1,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(2)] AS instab_score_median,
    APPROX_QUANTILES(cl.critical_lab_count, 4)[OFFSET(3)] AS instab_score_q3,
    NULL AS los_q1, NULL AS los_median, NULL AS los_q3,
    NULL AS mortality_count, NULL AS total_patients, NULL AS mortality_rate_percent
  FROM control_lab_events cl
)

SELECT * FROM cardiac_summary
UNION ALL
SELECT * FROM control_summary;