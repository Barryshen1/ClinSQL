WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 63 AND 73 AND a.admission_type = 'TRANSFER'
),
LOS AS (
  SELECT
    pi.subject_id,
    i.los
  FROM
    PatientInfo AS pi
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON pi.subject_id = i.subject_id
)
SELECT
  CASE
    WHEN pi.hospital_expire_flag = 1
    THEN 'In-hospital death'
    WHEN pi.discharge_location = 'HOME'
    THEN 'Discharged home'
    WHEN pi.discharge_location = 'HOSPICE'
    THEN 'Hospice'
    ELSE 'Other'
  END AS discharge_category,
  AVG(los.los) AS mean_los,
  STDDEV(los.los) AS sd_los
FROM
  LOS AS los
INNER JOIN
  PatientInfo AS pi
  ON los.subject_id = pi.subject_id
GROUP BY
  discharge_category;