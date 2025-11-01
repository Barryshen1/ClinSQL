WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69 AND a.admission_type = 'EMERGENCY'
), PatientOutcome AS (
  SELECT
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital mortality'
      ELSE 'Discharged alive'
    END AS outcome
  FROM
    PatientInfo
), PatientLOS AS (
  SELECT
    subject_id,
    los
  FROM
    PatientInfo
  WHERE
    los >= 7
)
SELECT
  po.outcome,
  COUNT(po.subject_id) AS count,
  COUNT(po.subject_id) * 100.0 / SUM(COUNT(po.subject_id)) OVER () AS proportion,
  PERCENTILE_CONT(pl.los, 0.5) OVER () AS percentile_rank_7_day_los
FROM
  PatientOutcome AS po
LEFT JOIN
  PatientLOS AS pl
  ON po.subject_id = pl.subject_id
GROUP BY
  po.outcome;