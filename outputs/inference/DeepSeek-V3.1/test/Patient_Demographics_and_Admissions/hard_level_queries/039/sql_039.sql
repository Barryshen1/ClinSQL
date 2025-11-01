WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) + 1 AS los, -- Add 1 to account for same-day discharges
    -- Check for death during index admission
    adm.deathtime IS NOT NULL AS died_in_admission,
    -- Check for readmission within 30 days
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm2 
      WHERE adm2.subject_id = adm.subject_id 
        AND adm2.admittime > adm.dischtime 
        AND adm2.admittime <= DATE_ADD(adm.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d,
    ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) as admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 10 AND diag.icd_code = 'J96.00') 
      OR 
      (diag.icd_version = 9 AND diag.icd_code = '518.81')
    )
),
-- Exclude index admissions where patient died and ensure first admission
cohort_clean AS (
  SELECT *
  FROM cohort
  WHERE NOT died_in_admission AND admission_rank = 1
)
-- Calculate metrics
SELECT 
  -- 30-day readmission rate
  COUNTIF(readmitted_30d) AS readmitted,
  COUNT(*) AS total_index_admissions,
  ROUND(COUNTIF(readmitted_30d) * 100.0 / COUNT(*), 2) AS readmission_rate_percent,
  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d THEN los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN NOT readmitted_30d THEN los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  -- Percent of index admissions with LOS > 9 days
  ROUND(COUNTIF(los > 9) * 100.0 / COUNT(*), 2) AS percent_los_gt_9_days
FROM cohort_clean;