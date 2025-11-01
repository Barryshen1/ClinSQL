WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    deathtime,
    admission_type,
    discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
), ICUStayInfo AS (
  SELECT
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  a.discharge_location,
  AVG(i.los) AS mean_los,
  APPROX_QUANTILES(i.los, 4) AS los_percentiles,
  PERCENTILE_CONT(0.5, i.los) OVER (PARTITION BY a.discharge_location ORDER BY i.los) AS los_percentile_rank
FROM
  AdmissionInfo AS a
INNER JOIN
  PatientInfo AS p ON a.subject_id = p.subject_id
INNER JOIN
  ICUStayInfo AS i ON a.hadm_id = i.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age = 42
  AND a.admission_type = 'EMERGENCY'
  AND p.anchor_age BETWEEN 37 AND 47
  AND a.discharge_location IN ('HOME', 'FACILITY', 'IN HOSPITAL')
GROUP BY
  a.discharge_location
ORDER BY
  a.discharge_location;