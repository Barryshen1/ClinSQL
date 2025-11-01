WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age BETWEEN 63 AND 73
    AND p.gender = 'F'
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON
    ic.hadm_id = a.hadm_id
  WHERE
    a.hospital_expire_flag = 0
), FilteredICUStayInfo AS (
  SELECT
    icsi.subject_id,
    icsi.hadm_id,
    icsi.stay_id,
    icsi.intime,
    icsi.outtime,
    icsi.los,
    icsi.discharge_location
  FROM
    ICUStayInfo AS icsi
  JOIN
    PatientInfo AS pi
  ON
    icsi.subject_id = pi.subject_id
)
SELECT
  discharge_location,
  COUNT(stay_id) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(stay_id) AS percent_le_10_days
FROM
  FilteredICUStayInfo
GROUP BY
  discharge_location
ORDER BY
  discharge_location;