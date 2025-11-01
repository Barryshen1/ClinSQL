WITH ami_cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id
   AND adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 44 AND 54
    AND (
      diag.icd_code LIKE '410%'     -- ICD9 AMI
      OR diag.icd_code LIKE 'I21%'  -- ICD10 AMI
      OR diag.icd_code LIKE 'I22%'  -- ICD10 recurrent AMI
    )
),
lab_instability AS (
  SELECT
    c.hadm_id,
    COUNTIF(LOWER(flag) IS NOT NULL AND LOWER(flag) != '') AS abnormal_lab_count
  FROM ami_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id = le.hadm_id
  WHERE le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
ami_summary AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(75)] AS p75_lab_instability,
    AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0) AS avg_los_days,
    SUM(c.hospital_expire_flag) / COUNT(*) AS mortality_rate
  FROM ami_cohort c
  JOIN lab_instability li
    ON c.hadm_id = li.hadm_id
),
critical_lab_freq AS (
  SELECT
    cohort_type,
    COUNTIF(LOWER(flag) IS NOT NULL AND LOWER(flag) != '') AS abnormal_count,
    COUNT(*) AS total_labs,
    COUNTIF(LOWER(flag) IS NOT NULL AND LOWER(flag) != '') / COUNT(*) AS abnormal_freq
  FROM (
    SELECT 'AMI' AS cohort_type, le.*
    FROM lab_instability li
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON li.hadm_id = le.hadm_id
    UNION ALL
    SELECT 'General' AS cohort_type, le.*
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  )
  GROUP BY cohort_type
)
SELECT
  ami_summary.p75_lab_instability,
  ami_summary.avg_los_days,
  ami_summary.mortality_rate,
  cf.cohort_type,
  cf.abnormal_count,
  cf.total_labs,
  cf.abnormal_freq
FROM ami_summary
JOIN critical_lab_freq cf
ON TRUE
ORDER BY cf.cohort_type;