WITH cohort AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.insurance,
    adm.admission_location,
    adm.deathtime,
    pat.gender,
    pat.anchor_age,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.anchor_age BETWEEN 51 AND 61
    AND pat.gender = 'M'
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '577.0') OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
),

index_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM cohort
  WHERE deathtime IS NULL OR deathtime > dischtime
),

readmission_flag AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id AS index_hadm,
    ia.admittime AS index_admittime,
    ia.dischtime AS index_dischtime,
    ia.los_days AS index_los,
    CASE 
      WHEN DATE_DIFF(LEAD(ia.admittime) OVER (PARTITION BY ia.subject_id ORDER BY ia.admittime), ia.dischtime, DAY) <= 30 
      THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM index_admissions ia
  WHERE ia.admission_rank = 1
)

SELECT 
  CASE WHEN readmitted_30d = 1 THEN 'Readmitted' ELSE 'Not Readmitted' END AS group_category,
  COUNT(*) AS num_patients,
  APPROXIMATE_QUANTILES(index_los, 100)[OFFSET(50)] AS median_los,
  ROUND(100.0 * SUM(CASE WHEN index_los > 9 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_gt_9
FROM readmission_flag
GROUP BY readmitted_30d;