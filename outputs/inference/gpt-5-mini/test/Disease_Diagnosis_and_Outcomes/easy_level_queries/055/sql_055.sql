WITH primary_aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    d.seq_num = 1
    AND UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
    AND (
      -- require 'acute' and either 'renal' or 'kidney' in the diagnosis description (case-insensitive)
      LOWER(COALESCE(dicd.long_title, '')) LIKE '%acute%' 
      AND (
        LOWER(COALESCE(dicd.long_title, '')) LIKE '%renal%'
        OR LOWER(COALESCE(dicd.long_title, '')) LIKE '%kidney%'
      )
    )
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_days_75th_percentile,
  COUNT(*) AS admissions_count
FROM primary_aki_admissions;