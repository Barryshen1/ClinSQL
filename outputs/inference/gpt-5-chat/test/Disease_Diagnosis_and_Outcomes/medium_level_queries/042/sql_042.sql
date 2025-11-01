WITH ami_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
         adm.hospital_expire_flag, adm.discharge_location,
         p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON adm.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')  -- AMI ICD-9
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')) -- AMI ICD-10
    )
),
shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '7855%') -- shock ICD-9
     OR (icd_version = 10 AND icd_code LIKE 'R57%')  -- shock ICD-10
),
resp_failure_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code IN ('51881','51882','51884')))
     OR (icd_version = 10 AND icd_code LIKE 'J96%')
),
cohort AS (
  SELECT *,
         DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days
  FROM ami_admissions
  WHERE hadm_id NOT IN (SELECT hadm_id FROM shock_admissions)
    AND hadm_id NOT IN (SELECT hadm_id FROM resp_failure_admissions)
),
cohort_with_los_group AS (
  SELECT *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '≥8 days'
      ELSE 'Unknown'
    END AS los_group
  FROM cohort
)
SELECT
  los_group,
  COUNT(*) AS admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_percent,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ARRAY_AGG(DISTINCT discharge_location IGNORE NULLS ORDER BY discharge_location) AS discharge_locations
FROM cohort_with_los_group
GROUP BY los_group
ORDER BY los_group;