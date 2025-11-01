WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.dischtime IS NOT NULL
    AND (
      LOWER(dicd.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%acute ischemic heart disease%'
      OR LOWER(dicd.long_title) LIKE '%unstable angina%'
      OR LOWER(dicd.long_title) LIKE '%non-st elevation myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%st elevation myocardial infarction%'
      OR LOWER(dicd.long_title) LIKE '%acute coronary syndrome%'
    )
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los_days
FROM
  filtered_admissions;