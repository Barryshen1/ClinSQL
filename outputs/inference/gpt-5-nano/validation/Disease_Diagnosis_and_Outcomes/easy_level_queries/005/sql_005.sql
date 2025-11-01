WITH ischemic_stroke_admissions AS (
  SELECT
    a.admittime,
    a.dischtime,
    p.gender,
    CASE
      WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE di.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%ischemic stroke%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)

SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM (
  SELECT
    DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM ischemic_stroke_admissions AS adm
  WHERE adm.gender = 'F'
    AND adm.age_at_adm BETWEEN 59 AND 69
);