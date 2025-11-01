WITH male_sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND (
      -- ICD-10 sepsis codes
      (d.icd_version = 10 AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%'))
      -- ICD-9 sepsis codes
      OR (d.icd_version = 9 AND (d.icd_code IN ('99591', '99592', '78552')))
    )
)

, lactate_labitems AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%lactate%'
    AND LOWER(fluid) = 'blood'
)

, discharge_day_lactate AS (
  SELECT
    msa.subject_id,
    msa.hadm_id,
    l.charttime,
    l.valuenum
  FROM
    male_sepsis_admissions msa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON msa.subject_id = l.subject_id AND msa.hadm_id = l.hadm_id
    INNER JOIN lactate_labitems li
      ON l.itemid = li.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(msa.dischtime)
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS lactate_25th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS lactate_75th_percentile,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS lactate_IQR
FROM
  discharge_day_lactate
;