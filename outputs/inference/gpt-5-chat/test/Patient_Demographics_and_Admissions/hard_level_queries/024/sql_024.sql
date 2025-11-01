WITH ischemic_stroke_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND (
        icd_code LIKE '433%1' OR
        icd_code LIKE '434%1' OR
        icd_code = '436'
    ))
    OR (icd_version = 10 AND (
        icd_code LIKE 'I63%'
    ))
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
   AND diag.seq_num = 1
  JOIN ischemic_stroke_codes c
    ON c.icd_code = diag.icd_code
   AND c.icd_version = diag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND UPPER(adm.insurance) LIKE '%MEDICARE%'
    AND UPPER(adm.admission_location) LIKE '%EMERGENCY%'
    AND adm.hospital_expire_flag = 0
),
readmissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE WHEN MIN(next.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmit_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next
    ON c.subject_id = next.subject_id
    AND next.admittime > c.dischtime
    AND next.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_flags AS (
  SELECT
    c.*,
    r.readmit_flag
  FROM cohort c
  JOIN readmissions r
    ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
)
SELECT
  COUNT(*) AS n_index_admissions,
  ROUND(100 * AVG(readmit_flag), 1) AS readmission_rate_pct,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 1) AS median_los_overall,
  ROUND(APPROX_QUANTILES(CASE WHEN readmit_flag=1 THEN los_days END, 100)[OFFSET(50)],1) AS median_los_readmitted,
  ROUND(APPROX_QUANTILES(CASE WHEN readmit_flag=0 THEN los_days END, 100)[OFFSET(50)],1) AS median_los_not_readmitted,
  ROUND(100 * AVG(CASE WHEN los_days > 5 THEN 1 ELSE 0 END), 1) AS pct_los_gt5
FROM cohort_with_flags;