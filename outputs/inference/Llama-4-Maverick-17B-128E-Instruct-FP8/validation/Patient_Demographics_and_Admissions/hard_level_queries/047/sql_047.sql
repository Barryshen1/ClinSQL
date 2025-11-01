WITH patient_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, 
         p.anchor_age, 
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.seq_num = 1 AND dicd.long_title LIKE '%Hemorrhagic stroke%' AND d.icd_version = 10
    )
),
readmissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, los,
         LAG(dischtime) OVER (PARTITION BY subject_id ORDER BY admittime) AS prev_dischtime
  FROM patient_cohort
),
readmission_labels AS (
  SELECT hadm_id, los,
         CASE 
           WHEN admittime <= DATE_ADD(prev_dischtime, INTERVAL 30 DAY) THEN 1 
           ELSE 0 
         END AS is_readmission,
         prev_dischtime
  FROM readmissions
)
SELECT 
  AVG(is_readmission) AS readmission_rate,
  APPROX_QUANTILES(CASE WHEN is_readmission = 1 THEN los END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN is_readmission = 0 THEN los END, 100)[OFFSET(50)] AS median_los_not_readmitted,
  AVG(CASE WHEN los > 4 THEN 1 ELSE 0 END) AS percent_los_gt_4
FROM readmission_labels
WHERE prev_dischtime IS NOT NULL;