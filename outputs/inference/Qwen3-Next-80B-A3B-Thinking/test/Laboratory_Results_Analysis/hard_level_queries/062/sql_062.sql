WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 43 AND 53
    AND di.long_title LIKE '%sepsis%'
),
lab_events AS (
  SELECT
    c.hadm_id,
    COUNT(l.labevent_id) AS critical_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL 72 HOUR
    AND l.flag = 'A'
  GROUP BY c.hadm_id
)
SELECT
  PERCENTILE_CONT(critical_count, 0.25) WITHIN GROUP (ORDER BY critical_count) AS percentile_25,
  COUNT(*) AS cohort_size,
  AVG(critical_count) AS mean_critical_events,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_percent
FROM cohort c
LEFT JOIN lab_events le ON c.hadm_id = le.hadm_id;