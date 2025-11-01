WITH index_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Check for readmission within 30 days
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2 
      WHERE adm2.subject_id = adm.subject_id 
        AND adm2.admittime > adm.dischtime 
        AND adm2.admittime <= DATETIME_ADD(adm.dischtime, INTERVAL 30 DAY)
    ) THEN 1 ELSE 0 END AS readmitted_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491', '436'))
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
    )
    -- Exclude in-hospital death for readmission risk set
    AND adm.deathtime IS NULL
),

readmission_stats AS (
  SELECT
    readmitted_30d,
    COUNT(*) AS num_index_admissions,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_los_gt_5
  FROM index_admissions
  GROUP BY readmitted_30d
)

SELECT
  -- 30-day readmission rate
  (SELECT num_index_admissions FROM readmission_stats WHERE readmitted_30d = 1) * 100.0 /
  (SELECT SUM(num_index_admissions) FROM readmission_stats) AS readmission_rate_percent,
  -- Median LOS for readmitted
  (SELECT median_los_days FROM readmission_stats WHERE readmitted_30d = 1) AS median_los_readmitted,
  -- Median LOS for non-readmitted
  (SELECT median_los_days FROM readmission_stats WHERE readmitted_30d = 0) AS median_los_non_readmitted,
  -- Percent index stays >5 days (overall)
  (SELECT SUM(CASE WHEN los_days > 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) FROM index_admissions) AS pct_index_los_gt_5
;