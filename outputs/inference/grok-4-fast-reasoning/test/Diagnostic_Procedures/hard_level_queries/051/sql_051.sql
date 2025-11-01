WITH cohort_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age >= 90
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code 
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id 
        AND LOWER(dd.long_title) LIKE '%sepsis%'
    )
),
cohort_stays AS (
  SELECT 
    ca.subject_id,
    ca.hadm_id, 
    i.stay_id, 
    i.intime
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON ca.hadm_id = i.hadm_id
),
first_24h_labs AS (
  SELECT 
    cs.stay_id, 
    COUNT(le.labevent_id) AS num_labs
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.hadm_id = cs.hadm_id 
    AND le.subject_id = cs.subject_id
  WHERE le.charttime >= cs.intime 
    AND le.charttime < TIMESTAMP_ADD(cs.intime, INTERVAL 1 DAY)
  GROUP BY cs.stay_id
),
diagnostics_stats AS (
  SELECT 
    STDDEV(num_labs) AS sd_diagnostics,
    PERCENTILE_CONT(num_labs, 0.75) AS p75_diagnostics,
    PERCENTILE_CONT(num_labs, 0.95) AS p95_diagnostics
  FROM first_24h_labs
),
admission_stats AS (
  SELECT 
    COUNT(*) AS num_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*) AS mortality_pct,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS avg_hosp_los_days
  FROM cohort_admissions
)
SELECT 
  ds.sd_diagnostics,
  ds.p75_diagnostics,
  ds.p95_diagnostics,
  ast.num_admissions,
  (SELECT COUNT(*) FROM cohort_stays) AS num_icu_stays,
  ast.mortality_pct,
  ast.avg_hosp_los_days
FROM diagnostics_stats ds
CROSS JOIN admission_stats ast;