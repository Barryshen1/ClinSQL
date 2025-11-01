WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.admission_location,
    adm.insurance,
    pat.gender,
    -- calculate admission age
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS admission_age,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
   AND dx.seq_num = 1 -- principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dxd
    ON dx.icd_code = dxd.icd_code
   AND dx.icd_version = dxd.icd_version
  WHERE pat.gender = 'F'
    AND adm.insurance = 'Medicare'
    AND admission_location = 'TRANSFER FROM ANOTHER HOSPITAL'
    AND ( (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
       OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I21%') )
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 76 AND 86
),
readmissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(a.admittime) AS next_admit_time
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
    AND a.admittime > c.dischtime
    AND a.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_readmit AS (
  SELECT
    c.*,
    CASE WHEN r.next_admit_time IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM cohort c
  LEFT JOIN readmissions r
    ON c.subject_id = r.subject_id
   AND c.hadm_id = r.hadm_id
)
-- Final aggregation
SELECT
  COUNT(*) AS cohort_size,
  ROUND(100 * SUM(readmit_30d) / COUNT(*), 1) AS readmit_30d_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_overall,
  APPROX_QUANTILES(IF(readmit_30d=1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmit,
  APPROX_QUANTILES(IF(readmit_30d=0, los_days, NULL), 100)[OFFSET(50)] AS median_los_not_readmit,
  ROUND(100 * SUM(CASE WHEN los_days > 4 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_los_gt4
FROM cohort_with_readmit;