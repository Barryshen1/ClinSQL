WITH stroke_admissions AS (
  SELECT
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dic
    ON adm.hadm_id = dic.hadm_id
    AND adm.subject_id = dic.subject_id
  WHERE
    pat.gender = 'F'
    AND adm.dischtime IS NOT NULL
    AND dic.seq_num = 1
    AND (
      (dic.icd_version = 9 AND dic.icd_code IN (
        '43301', '43311', '43321', '43331', '43381', '43391',
        '43401', '43411', '43491', '436'
      ))
      OR (dic.icd_version = 10 AND dic.icd_code LIKE 'I63%')
    )
    AND (
      pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
    ) BETWEEN 59 AND 69
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM
  stroke_admissions;