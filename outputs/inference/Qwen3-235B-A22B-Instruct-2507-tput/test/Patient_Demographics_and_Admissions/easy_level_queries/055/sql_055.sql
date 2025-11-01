SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(24)] AS percentile_25_los_days
FROM (
  SELECT
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 49 AND 59
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
WHERE
  los_days >= 0;