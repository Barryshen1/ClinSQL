WITH acs_codes AS (
  -- Identify ICD entries that likely represent ACS (text-based)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute coronary%'
     OR LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%unstable angina%'
),

acs_hadm AS (
  -- For each admission that has any ACS diagnosis, flag if any ACS diag is primary (seq_num = 1)
  SELECT d.subject_id,
         d.hadm_id,
         MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acs_codes c
    ON d.icd_code = c.icd_code
   AND d.icd_version = c.icd_version
  GROUP BY d.subject_id, d.hadm_id
),

cohort AS (
  -- Build cohort: male patients age 83-93 with an ACS-coded admission, compute LOS group and diagnosis type
  SELECT a.subject_id,
         a.hadm_id,
         p.gender,
         p.anchor_age,
         DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 AS los_days,
         CASE
           WHEN DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 BETWEEN 1 AND 4 THEN '1-4'
           WHEN DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) + 1 BETWEEN 5 AND 7 THEN '5-7'
           ELSE NULL
         END AS los_group,
         CASE WHEN ah.has_primary_acs = 1 THEN 'primary' ELSE 'secondary' END AS diag_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN acs_hadm ah
    ON a.subject_id = ah.subject_id
   AND a.hadm_id = ah.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),

ultrasounds AS (
  -- Count HCPCS events per admission where the description indicates an ultrasound
  SELECT h.hadm_id,
         COUNT(1) AS us_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE LOWER(COALESCE(h.short_description, '') || ' ' || COALESCE(d.long_description, '')) LIKE '%ultrasound%'
  GROUP BY h.hadm_id
)

SELECT
  c.los_group,
  c.diag_type,
  COUNT(*) AS n_admissions,
  ROUND(AVG(COALESCE(u.us_count, 0)), 2) AS mean_ultrasounds_per_admission,
  MIN(COALESCE(u.us_count, 0)) AS min_ultrasounds_per_admission,
  MAX(COALESCE(u.us_count, 0)) AS max_ultrasounds_per_admission
FROM cohort c
LEFT JOIN ultrasounds u
  ON c.hadm_id = u.hadm_id
WHERE c.los_group IS NOT NULL
GROUP BY c.los_group, c.diag_type
ORDER BY c.los_group, c.diag_type;