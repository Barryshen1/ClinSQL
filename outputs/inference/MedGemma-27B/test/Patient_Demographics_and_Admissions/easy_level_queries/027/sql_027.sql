WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
)
SELECT
  PERCENTILE_CONT(0.25, los) AS q1,
  PERCENTILE_CONT(0.75, los) AS q3
FROM
  AdmissionInfo
WHERE
  gender = 'F' AND anchor_age BETWEEN 77 AND 87
  AND hadm_id IN (
    SELECT
      MIN(hadm_id)
    FROM
      AdmissionInfo
    WHERE
      subject_id = AdmissionInfo.subject_id
    GROUP BY
      subject_id
  );