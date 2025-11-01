WITH sepsis_icd_codes AS (
  -- List of ICD codes for sepsis (ICD-9 and ICD-10)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    REGEXP_CONTAINS(icd_code, r'^A40') OR
    REGEXP_CONTAINS(icd_code, r'^A41') OR
    REGEXP_CONTAINS(icd_code, r'^99591') OR
    REGEXP_CONTAINS(icd_code, r'^99592') OR
    REGEXP_CONTAINS(icd_code, r'^78552') OR
    REGEXP_CONTAINS(icd_code, r'^038') OR
    REGEXP_CONTAINS(icd_code, r'^9959')
),
sepsis_admissions AS (
  -- Admissions with sepsis diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN sepsis_icd_codes s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
),
cohort AS (
  -- Male ICU patients age 90-100 with sepsis
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    p.gender,
    p.anchor_age,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN sepsis_admissions s
    ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
diagnostic_utilization AS (
  -- For each ICU stay in cohort, count unique diagnoses for the admission
  SELECT
    c.stay_id,
    c.hadm_id,
    COUNT(DISTINCT d.icd_code) AS num_diagnoses
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.stay_id, c.hadm_id
),
cohort_stats AS (
  -- Calculate requested statistics for cohort
  SELECT
    COUNT(DISTINCT du.hadm_id) AS num_admissions,
    COUNT(DISTINCT du.stay_id) AS num_icu_stays,
    ROUND(AVG(c.los), 2) AS avg_los,
    ROUND(100 * SUM(a.hospital_expire_flag) / COUNT(a.hospital_expire_flag), 2) AS in_hospital_mortality_pct,
    ROUND(STDDEV(num_diagnoses), 2) AS sd_diagnostic_utilization
  FROM diagnostic_utilization du
  INNER JOIN cohort c
    ON du.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
),
cohort_percentiles AS (
  SELECT
    ROUND(quantiles[OFFSET(75)], 2) AS p75_diagnostic_utilization,
    ROUND(quantiles[OFFSET(95)], 2) AS p95_diagnostic_utilization
  FROM (
    SELECT APPROX_QUANTILES(num_diagnoses, 100) AS quantiles
    FROM diagnostic_utilization
  )
),
overall_icu AS (
  -- All ICU stays (for comparison)
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
overall_diagnostic_utilization AS (
  -- For each ICU stay, count unique diagnoses for the admission
  SELECT
    o.stay_id,
    o.hadm_id,
    COUNT(DISTINCT d.icd_code) AS num_diagnoses
  FROM overall_icu o
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON o.hadm_id = d.hadm_id
  GROUP BY o.stay_id, o.hadm_id
),
overall_stats AS (
  -- Calculate requested statistics for overall ICU
  SELECT
    COUNT(DISTINCT du.hadm_id) AS num_admissions,
    COUNT(DISTINCT du.stay_id) AS num_icu_stays,
    ROUND(AVG(o.los), 2) AS avg_los,
    ROUND(100 * SUM(a.hospital_expire_flag) / COUNT(a.hospital_expire_flag), 2) AS in_hospital_mortality_pct,
    ROUND(STDDEV(num_diagnoses), 2) AS sd_diagnostic_utilization
  FROM overall_diagnostic_utilization du
  INNER JOIN overall_icu o
    ON du.stay_id = o.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON o.hadm_id = a.hadm_id
),
overall_percentiles AS (
  SELECT
    ROUND(quantiles[OFFSET(75)], 2) AS p75_diagnostic_utilization,
    ROUND(quantiles[OFFSET(95)], 2) AS p95_diagnostic_utilization
  FROM (
    SELECT APPROX_QUANTILES(num_diagnoses, 100) AS quantiles
    FROM overall_diagnostic_utilization
  )
)
SELECT
  'Male ICU patients age 90-100 with sepsis' AS population,
  cs.num_admissions,
  cs.num_icu_stays,
  cs.avg_los,
  cs.in_hospital_mortality_pct,
  cs.sd_diagnostic_utilization,
  cp.p75_diagnostic_utilization,
  cp.p95_diagnostic_utilization
FROM cohort_stats cs
CROSS JOIN cohort_percentiles cp
UNION ALL
SELECT
  'All ICU patients' AS population,
  os.num_admissions,
  os.num_icu_stays,
  os.avg_los,
  os.in_hospital_mortality_pct,
  os.sd_diagnostic_utilization,
  op.p75_diagnostic_utilization,
  op.p95_diagnostic_utilization
FROM overall_stats os
CROSS JOIN overall_percentiles op
;