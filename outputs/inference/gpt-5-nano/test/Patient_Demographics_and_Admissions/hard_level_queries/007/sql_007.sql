WITH index_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS index_los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diac
      ON a.subject_id = diac.subject_id
     AND a.hadm_id = diac.hadm_id
     AND diac.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
      ON diac.icd_code = d.icd_code
     AND diac.icd_version = d.icd_version
  WHERE LOWER(a.admission_type) = 'emergency'
    AND LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 83 AND 93
    AND LOWER(a.insurance) LIKE '%medicare%'
    -- Principal TIA: ICD-9 435.x or ICD-10 G45.x
    AND ( (diac.icd_version = 9 AND diac.icd_code LIKE '435%')
          OR (diac.icd_version = 10 AND diac.icd_code LIKE 'G45%') )
    -- Robust: ensure TIAs are captured via title as well
    AND (d.long_title LIKE '%Transient ischemic attack%' OR d.long_title LIKE '%TIA%')
)

, cohort_with_read AS (
  SELECT ic.*,
     CASE WHEN EXISTS (
       SELECT 1
       FROM `physionet-data.mimiciv_3_1_hosp.admissions` na
       WHERE na.subject_id = ic.subject_id
         AND na.admittime > ic.dischtime
         AND na.admittime <= TIMESTAMP_ADD(ic.dischtime, INTERVAL 30 DAY)
     )
     THEN 1 ELSE 0 END AS readmit_30
  FROM index_cohort ic
)

SELECT
  AVG(readmit_30) AS thirty_day_readmission_rate,
  -- Median index LOS for readmitted vs non-readmitted (approximated)
  APPROX_MEDIAN(CASE WHEN readmit_30 = 1 THEN index_los_days END) AS median_index_los_days_readmitted,
  APPROX_MEDIAN(CASE WHEN readmit_30 = 0 THEN index_los_days END) AS median_index_los_days_nonreadmitted,
  -- Percent of index stays with LOS > 10 days
  100.0 * SUM(CASE WHEN index_los_days > 10 THEN 1 ELSE 0 END) / COUNT(*) AS pct_index_los_gt_10_days
FROM cohort_with_read;