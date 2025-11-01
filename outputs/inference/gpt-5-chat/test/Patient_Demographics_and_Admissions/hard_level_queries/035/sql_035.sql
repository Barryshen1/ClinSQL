WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS admit_seq
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND diag.seq_num = 1
  WHERE pat.gender = 'M'
    AND adm.insurance = 'Medicare'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 68 AND 78
    AND LOWER(adm.admission_location) LIKE '%skilled nursing facility%'
    AND (
         (diag.icd_version = 9 AND diag.icd_code = '5990')
      OR (diag.icd_version = 10 AND diag.icd_code = 'N390')
        )
    AND adm.dischtime IS NOT NULL
),
readmissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    MIN(next_adm.admittime) AS next_admit_time
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON c.subject_id = next_adm.subject_id
    AND next_adm.admittime > c.dischtime
    AND DATETIME_DIFF(next_adm.admittime, c.dischtime, DAY) <= 30
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.los_days
),
flagged AS (
  SELECT
    *,
    CASE WHEN next_admit_time IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d,
    CASE WHEN los_days > 6 THEN 1 ELSE 0 END AS los_gt6
  FROM readmissions
)
SELECT
  COUNT(*) AS total_index_admissions,
  ROUND(SUM(readmit_30d)/COUNT(*)*100, 2) AS readmit_rate_pct,
  -- median LOS for readmitted
  ROUND( APPROX_QUANTILES(IF(readmit_30d=1, los_days, NULL), 100)[OFFSET(50)], 2 ) AS median_los_readmit,
  -- median LOS for non-readmitted
  ROUND( APPROX_QUANTILES(IF(readmit_30d=0, los_days, NULL), 100)[OFFSET(50)], 2 ) AS median_los_no_readmit,
  ROUND(SUM(los_gt6)/COUNT(*)*100, 2) AS pct_los_gt6
FROM flagged;