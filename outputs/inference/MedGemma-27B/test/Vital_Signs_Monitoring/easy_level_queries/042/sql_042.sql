WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age = 68
), RelevantPatients AS (
  SELECT
    p.subject_id
  FROM PatientInfo AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
), MaxRR AS (
  SELECT
    rp.subject_id,
    MAX(ce.valuenum) AS max_rr
  FROM RelevantPatients AS rp
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS is_
    ON rp.subject_id = is_.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON is_.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220187 -- Respiratory Rate
  GROUP BY
    rp.subject_id
)
SELECT
  STDDEV(max_rr)
FROM MaxRR;