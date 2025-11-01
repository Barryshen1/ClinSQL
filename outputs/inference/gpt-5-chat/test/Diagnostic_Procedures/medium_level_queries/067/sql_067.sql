WITH acs_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.anchor_age,
    p.gender,
    DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) AS los_days,
    -- ACS type: primary or secondary
    CASE 
      WHEN MIN(CASE WHEN diag.seq_num = 1 AND (
            LOWER(diag_title.long_title) LIKE '%acute coronary%'
         OR LOWER(diag_title.long_title) LIKE '%myocardial infarction%'
         OR LOWER(diag_title.long_title) LIKE '%unstable angina%'
         OR LOWER(diag_title.long_title) LIKE '%angina pectoris%'
         ) THEN 1 ELSE 0 END) = 1
      THEN 'primary'
      ELSE 'secondary'
    END AS acs_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id
    AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS diag_title
    ON diag.icd_code = diag_title.icd_code 
    AND diag.icd_version = diag_title.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND DATE_DIFF(DATE(adm.dischtime), DATE(adm.admittime), DAY) BETWEEN 1 AND 7
    AND (
      LOWER(diag_title.long_title) LIKE '%acute coronary%'
      OR LOWER(diag_title.long_title) LIKE '%myocardial infarction%'
      OR LOWER(diag_title.long_title) LIKE '%unstable angina%'
      OR LOWER(diag_title.long_title) LIKE '%angina pectoris%'
    )
  GROUP BY adm.subject_id, adm.hadm_id, p.anchor_age, p.gender, adm.admittime, adm.dischtime
),
ultrasound_counts AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.los_days,
    ca.acs_type,
    CASE 
      WHEN ca.los_days BETWEEN 1 AND 4 THEN 'LOS_1_4'
      WHEN ca.los_days BETWEEN 5 AND 7 THEN 'LOS_5_7'
    END AS los_group,
    COUNTIF(LOWER(proc_title.long_title) LIKE '%ultrasound%' 
         OR LOWER(proc_title.long_title) LIKE '%echo%') AS us_count
  FROM acs_admissions AS ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON ca.subject_id = proc.subject_id
    AND ca.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS proc_title
    ON proc.icd_code = proc_title.icd_code
    AND proc.icd_version = proc_title.icd_version
  GROUP BY ca.subject_id, ca.hadm_id, ca.los_days, ca.acs_type, los_group
)
SELECT
  los_group,
  acs_type,
  PERCENTILE_CONT(us_count, 0.25) OVER (PARTITION BY los_group, acs_type) AS p25_us,
  PERCENTILE_CONT(us_count, 0.50) OVER (PARTITION BY los_group, acs_type) AS p50_us,
  PERCENTILE_CONT(us_count, 0.75) OVER (PARTITION BY los_group, acs_type) AS p75_us
FROM ultrasound_counts
ORDER BY los_group, acs_type;