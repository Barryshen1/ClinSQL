WITH PatientInfo AS (
  SELECT
    subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 77 AND 87
),
DialysisPatients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON d.subject_id = p.subject_id
  WHERE
    di.long_title LIKE '%dialysis%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN DialysisPatients AS dp
    ON s.subject_id = dp.subject_id
  WHERE
    s.stay_id = (
      SELECT
        MIN(stay_id)
      FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s2
      WHERE
        s2.subject_id = s.subject_id
    )
)
SELECT
  PERCENTILE_CONT(0.25, los) AS q1,
  PERCENTILE_CONT(0.75, los) AS q3,
  PERCENTILE_CONT(0.75, los) - PERCENTILE_CONT(0.25, los) AS IQR
FROM (
  SELECT
    (TIMESTAMP_DIFF(outtime, intime, DAY) + 1) AS los
  FROM ICUStays
);