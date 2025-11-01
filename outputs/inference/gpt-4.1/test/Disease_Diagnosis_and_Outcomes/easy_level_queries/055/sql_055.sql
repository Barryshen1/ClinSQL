SELECT
  APPROX_QUANTILES(
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY),
    4
  )[OFFSET(3)] AS los_75th_percentile_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions a
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 37 AND 47
  AND d.seq_num = 1
  AND (
    -- ICD-9 AKI: 584*
    (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '584')
    -- ICD-10 AKI: N17*
    OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'N17')
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0;