WITH first_stays_all AS (
  SELECT 
    i.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.los, 
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),
first_stays AS (
  SELECT 
    fsa.*,
    p.gender,
    p.anchor_age
  FROM first_stays_all fsa
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON fsa.subject_id = p.subject_id
  WHERE fsa.rn = 1
),
cohort_stays AS (
  SELECT 
    fs.subject_id,
    fs.stay_id,
    fs.hadm_id,
    fs.intime,
    fs.los,
    fs.hospital_expire_flag
  FROM first_stays fs
  WHERE fs.gender = 'F'
    AND fs.anchor_age BETWEEN 56 AND 66
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = fs.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '431%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
        )
    )
),
diag_intensity AS (
  SELECT 
    cs.stay_id,
    cs.los,
    cs.hospital_expire_flag,
    COUNT(le.labevent_id) AS num_diagnostics
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON cs.subject_id = le.subject_id 
    AND cs.hadm_id = le.hadm_id
    AND le.charttime >= cs.intime
    AND le.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 72 HOUR)
  GROUP BY cs.stay_id, cs.los, cs.hospital_expire_flag
),
cohort_summary AS (
  SELECT 
    PERCENTILE_CONT(num_diagnostics, 0.95) AS p95_diagnostic_intensity,
    AVG(los) AS mean_los_cohort,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_cohort
  FROM diag_intensity
),
all_summary AS (
  SELECT 
    AVG(los) AS mean_los_all,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_all
  FROM first_stays_all
  WHERE rn = 1
)
SELECT 
  cs.p95_diagnostic_intensity,
  cs.mean_los_cohort,
  cs.mortality_rate_cohort,
  a.mean_los_all,
  a.mortality_rate_all
FROM cohort_summary cs
CROSS JOIN all_summary a;