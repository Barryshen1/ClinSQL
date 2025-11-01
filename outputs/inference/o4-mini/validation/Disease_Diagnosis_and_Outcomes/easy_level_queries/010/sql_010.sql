WITH copd_exacerbation_adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
      AND d.seq_num    = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND UPPER(dd.long_title) LIKE '%COPD%'
    AND UPPER(dd.long_title) LIKE '%EXACERBATION%'
)
SELECT
  -- APPROX_QUANTILES returns an array of 5 values: [min, 25th, 50th, 75th, max]
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS los_25th_percentile_days
FROM
  copd_exacerbation_adms;