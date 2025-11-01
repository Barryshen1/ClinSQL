WITH relevant_patients AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
medications AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%hydralazine%' OR p.drug LIKE '%isosorbide dinitrate%'
),
admission_durations AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    a.admittime,
    a.dischtime,
    m.starttime,
    m.stoptime
  FROM medications AS m
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON m.subject_id = a.subject_id AND m.hadm_id = a.hadm_id
)
SELECT
  MIN(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS shortest_duration
FROM admission_durations AS a;