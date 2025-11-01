WITH stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    p.gender,
    CASE
      WHEN p.anchor_age IS NOT NULL AND p.anchor_year IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code AND dd.icd_version = di.icd_version
  WHERE di.seq_num = 1
    AND (LOWER(dd.long_title) LIKE '%ischemic stroke%' OR LOWER(dd.long_title) LIKE '%cerebral infarction%')
)
SELECT
  -- IQR in days
  (q[OFFSET(3)] - q[OFFSET(1)]) AS iqr_days
FROM (
  SELECT APPROX_QUANTILES(los_days, 4) AS q
  FROM stroke_admissions
  WHERE UPPER(gender) = 'F'
    AND age_at_adm BETWEEN 71 AND 81
) AS sub;