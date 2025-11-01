WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM (
        SELECT
          hadm_id,
          ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.admissions`
      )
      WHERE rn = 1
    )
),
anticoag_patients AS (
  SELECT DISTINCT
    fa.*
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    fa.hadm_id = pr.hadm_id
  WHERE
    REGEXP_CONTAINS(LOWER(pr.drug), r'warfarin|heparin|apixaban|rivaroxaban|dabigatran|enoxaparin|fondaparinux')
)
SELECT
  STDDEV_SAMP(los_days) AS los_sd
FROM
  anticoag_patients;