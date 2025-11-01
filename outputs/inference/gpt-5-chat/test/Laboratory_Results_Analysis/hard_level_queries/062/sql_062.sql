WITH sepsis_cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
         adm.hospital_expire_flag, pat.anchor_age, pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND LOWER(ddx.long_title) LIKE '%sepsis%'
),
critical_lab_events AS (
  SELECT sc.hadm_id,
         COUNT(*) AS event_count
  FROM sepsis_cohort sc
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sc.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY sc.hadm_id
),
cohort_with_events AS (
  SELECT sc.*,
         IFNULL(cle.event_count, 0) AS event_count,
         TIMESTAMP_DIFF(sc.dischtime, sc.admittime, HOUR) / 24.0 AS los_days
  FROM sepsis_cohort sc
  LEFT JOIN critical_lab_events cle
    ON sc.hadm_id = cle.hadm_id
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(AVG(event_count), 2) AS mean_events_per_admission,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(hospital_expire_flag)*100, 2) AS mortality_rate_percent,
  APPROX_QUANTILES(event_count, 100)[OFFSET(25)] AS p25_event_count
FROM cohort_with_events;