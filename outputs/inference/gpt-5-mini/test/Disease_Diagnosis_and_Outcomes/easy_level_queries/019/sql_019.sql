SELECT
  STDDEV_SAMP(los_days) AS sd_los_days,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS mean_los_days
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
    AND dx.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON dx.icd_code = dic.icd_code
    AND dx.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      LOWER(dic.long_title) LIKE '%sepsis%'
      OR LOWER(dic.long_title) LIKE '%septic%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) > 0
)
;