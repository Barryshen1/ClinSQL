SELECT
  APPROX_QUANTILES(los_hours / 24.0, 100)[OFFSET(75)] AS p75_los_days
FROM (
  SELECT
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  INNER JOIN (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON
      diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
    WHERE
      diag.seq_num = 1
      AND LOWER(d_diag.long_title) LIKE '%upper gastrointestinal bleed%'
  ) primary_gi
  ON
    a.hadm_id = primary_gi.hadm_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) = 70
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
);