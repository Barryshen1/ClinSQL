WITH relevant_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 51 AND 61
),
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON i.hadm_id = a.hadm_id
  INNER JOIN
    relevant_patients AS p ON i.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND i.stay_id IN (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = i.subject_id
      GROUP BY
        subject_id
    )
)
SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS percentile_25
FROM
  first_icu_stays;