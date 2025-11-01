WITH
-- AMI ICD codes
ami_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410'))
    OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^I21') OR REGEXP_CONTAINS(icd_code, r'^I22')))
),
-- Shock ICD codes
shock_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^7855'))
    OR (icd_version = 10 AND (REGEXP_CONTAINS(icd_code, r'^R57') OR REGEXP_CONTAINS(icd_code, r'^I95')))
),
-- Respiratory failure ICD codes
respfail_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (icd_code = '51881' OR icd_code = '51884'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J96'))
),
-- Admissions with AMI
ami_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN ami_icd ami
    ON d.icd_code = ami.icd_code AND d.icd_version = ami.icd_version
),
-- Admissions with shock
shock_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN shock_icd s
    ON d.icd_code = s.icd_code AND d.icd_version = s.icd_version
),
-- Admissions with respiratory failure
respfail_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN respfail_icd r
    ON d.icd_code = r.icd_code AND d.icd_version = r.icd_version
),
-- Main cohort: men 69-79, AMI, no shock/resp fail
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ami_admissions ami
    ON a.hadm_id = ami.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hadm_id NOT IN (SELECT hadm_id FROM shock_admissions)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM respfail_admissions)
),
-- Add LOS category
cohort_los AS (
  SELECT
    *,
    CASE
      WHEN los BETWEEN 1 AND 3 THEN '1-3'
      WHEN los BETWEEN 4 AND 7 THEN '4-7'
      WHEN los >= 8 THEN '8+'
      ELSE NULL
    END AS los_group
  FROM cohort
  WHERE los >= 1 -- Exclude LOS < 1 day
)
-- Final aggregation
SELECT
  los_group,
  COUNT(*) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS mortality_percent,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  discharge_location,
  COUNT(*) AS n_discharge,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY los_group) * 100, 1) AS discharge_pct
FROM cohort_los
WHERE los_group IS NOT NULL
GROUP BY los_group, discharge_location
ORDER BY
  CASE los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '8+' THEN 3
    ELSE 4
  END,
  n_discharge DESC;