WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 81 AND 91
),
PrescriptionDetails AS (
  SELECT
    rx.subject_id,
    rx.hadm_id,
    rx.starttime,
    rx.stoptime,
    rx.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS rx
  WHERE
    rx.drug LIKE '%dihydropyridine%' OR rx.drug LIKE '%CCB%'
),
PrescriptionDurations AS (
  SELECT
    pd.subject_id,
    pd.hadm_id,
    DATE_DIFF(pd.stoptime, pd.starttime, DAY) AS duration_days
  FROM
    PrescriptionDetails AS pd
  WHERE
    pd.subject_id IN (SELECT subject_id FROM PatientCohort)
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS percentile_25
FROM
  PrescriptionDurations;