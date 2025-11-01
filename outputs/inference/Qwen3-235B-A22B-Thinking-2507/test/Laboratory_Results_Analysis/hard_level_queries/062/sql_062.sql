WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND (d.icd_code LIKE '038%' OR d.icd_code IN ('99591', '99592')))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R652%'))
        )
    )
),
lab_counts AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS hospital_los,
    COUNT(le.labevent_id) AS count_critical
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime <= c.admittime + INTERVAL '72' HOUR
    AND le.flag IS NOT NULL
  GROUP BY c.hadm_id, c.hospital_expire_flag, hospital_los
)
SELECT 
  APPROX_QUANTILES(count_critical, 100)[OFFSET(24)] AS p25_instability,
  COUNT(*) AS cohort_size,
  AVG(count_critical) AS mean_critical_events,
  AVG(hospital_los) AS mean_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM lab_counts;