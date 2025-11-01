WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    LOWER(dd.long_title) AS diag_title,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING (subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.seq_num = 1
    AND (
      LOWER(dd.long_title) LIKE '%hemorrhag%' OR
      LOWER(dd.long_title) LIKE '%subarachnoid%' OR
      LOWER(dd.long_title) LIKE '%intracerebral%' OR
      LOWER(dd.long_title) LIKE '%intracranial%' OR
      LOWER(dd.long_title) LIKE '%bleed%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(75)] AS los_75th_pct_days,
  COUNT(*) AS n_admissions
FROM cohort
WHERE los_days IS NOT NULL;