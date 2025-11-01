WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (60*60*24) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE 
    p.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND (adm.admission_location LIKE '%SKILLED NURSING%' OR adm.admission_location LIKE '%SNF%')
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%')
    )
    AND adm.hospital_expire_flag = 0
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 61 AND 71
),
index_with_readmission AS (
  SELECT 
    ia.*,
    CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
        WHERE next_adm.subject_id = ia.subject_id
          AND next_adm.admittime > ia.dischtime
          AND next_adm.admittime <= ia.dischtime + INTERVAL '30' DAY
          AND next_adm.hadm_id != ia.hadm_id
    ) THEN 1 ELSE 0 END AS has_readmission
  FROM index_admissions ia
)
SELECT 
  (COUNTIF(has_readmission = 1) * 100.0 / COUNT(*)) AS readmission_rate_percent,
  APPROX_QUANTILES(IF(has_readmission = 1, los_days, NULL), 1000)[OFFSET(500)] AS median_los_readmitted_days,
  APPROX_QUANTILES(IF(has_readmission = 0, los_days, NULL), 1000)[OFFSET(500)] AS median_los_nonreadmitted_days,
  (COUNTIF(los_days > 6) * 100.0 / COUNT(*)) AS percent_los_gt6
FROM index_with_readmission;