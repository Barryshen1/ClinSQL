WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'HOSPITAL'
), ICUStayInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
      ON a.hadm_id = i.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
)
SELECT
  discharge_location,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 4) AS percentiles,
  COUNT(CASE WHEN los <= 10 THEN 1 ELSE NULL END) * 100.0 / COUNT(los) AS percent_le_10_days
FROM
  ICUStayInfo
  INNER JOIN PatientInfo
    ON ICUStayInfo.subject_id = PatientInfo.subject_id
GROUP BY
  discharge_location
ORDER BY
  discharge_location;