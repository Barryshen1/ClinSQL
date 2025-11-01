SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(25)] AS los_p25_days,
  COUNT(*) AS n_admissions
FROM (
  SELECT
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
    -- text-based filter to capture COPD exacerbation diagnoses across ICD versions
    AND (
      LOWER(dd.long_title) LIKE '%exacerb%' 
      AND (
        LOWER(dd.long_title) LIKE '%copd%'
        OR LOWER(dd.long_title) LIKE '%chronic obstructive%'
        OR LOWER(dd.long_title) LIKE '%bronchitis%'
        OR LOWER(dd.long_title) LIKE '%emphysema%'
      )
    )
);