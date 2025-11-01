WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 55
    AND gender = 'F'
), AdmissionInfo AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    a.admittime = (
      SELECT
        MIN(admittime)
      FROM
        `physionet-data.mimiciv_3_1_hosp.admissions`
      WHERE
        subject_id = a.subject_id
    )
), AnticoagulantInfo AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON a.subject_id = e.subject_id
    AND a.hadm_id = e.hadm_id
  WHERE
    e.medication LIKE '%anticoagulant%'
), ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    AdmissionInfo AS a
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id
    AND a.hadm_id = i.hadm_id
  WHERE
    i.stay_id = (
      SELECT
        MIN(stay_id)
      FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE
        subject_id = i.subject_id
        AND hadm_id = i.hadm_id
    )
), AgeGroupInfo AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age BETWEEN 50 AND 60
    AND gender = 'F'
)
SELECT
  AVG(i.outtime - i.intime) AS median_icu_los_days
FROM
  ICUStayInfo AS i
JOIN
  AnticoagulantInfo AS a
  ON i.subject_id = a.subject_id
  AND i.hadm_id = a.hadm_id
JOIN
  AgeGroupInfo AS ag
  ON i.subject_id = ag.subject_id
  AND i.hadm_id = ag.hadm_id;