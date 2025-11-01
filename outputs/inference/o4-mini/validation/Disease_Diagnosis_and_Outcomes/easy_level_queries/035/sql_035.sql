SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
      ON a.subject_id = diag.subject_id
     AND a.hadm_id    = diag.hadm_id
     AND diag.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON diag.icd_code    = dd.icd_code
     AND diag.icd_version = dd.icd_version
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender       = 'M'
    AND p.anchor_age = 70
    AND LOWER(dd.long_title) LIKE '%upper gastrointestinal bleed%'
);