SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days
FROM (
  SELECT
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400 AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND d_icd.seq_num = 1
    AND LOWER(d.long_title) LIKE '%copd%'
    AND LOWER(d.long_title) LIKE '%exacerb%'
    AND a.dischtime IS NOT NULL
) AS los_data;