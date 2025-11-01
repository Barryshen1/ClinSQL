WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 43 AND 53
),
FirstICUAdmission AS (
  SELECT
    p.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN
    PatientInfo AS p
    ON i.subject_id = p.subject_id
  WHERE
    i.stay_id IN (
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
  PERCENTILE_CONT(0.25, TIMESTAMP_DIFF(outtime, intime, DAY)) AS percentile_25_icu_los_days
FROM
  FirstICUAdmission;