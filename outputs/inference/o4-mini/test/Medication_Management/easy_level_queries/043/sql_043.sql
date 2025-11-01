WITH eligible_stays AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS stay_length_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
      ON a.hadm_id = rx.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(rx.drug) LIKE '%hydralazine%'
      OR LOWER(rx.drug) LIKE '%isosorbide dinitrate%'
    )
)
SELECT
  MIN(stay_length_days) AS shortest_inpatient_duration_days
FROM
  eligible_stays;