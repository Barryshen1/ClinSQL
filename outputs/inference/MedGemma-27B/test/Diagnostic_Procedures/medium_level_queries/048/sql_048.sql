WITH PatientHF AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
  INTERSECT
  SELECT
    DISTINCT
    d.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%heart failure%'
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los,
    a.admission_type,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientHF
    )
), ImagingEvents AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
  WHERE
    h.hcpcs_cd LIKE '7%' -- Codes for imaging procedures
  GROUP BY
    h.hadm_id
), LOSGroup AS (
  SELECT
    ai.hadm_id,
    ai.los,
    CASE
      WHEN ai.los BETWEEN 1 AND 3
      THEN '1-3 days'
      WHEN ai.los BETWEEN 4 AND 7
      THEN '4-7 days'
      ELSE 'Other'
    END AS los_group
  FROM
    AdmissionInfo AS ai
)
SELECT
  lg.los_group,
  ai.admission_type,
  COUNT(DISTINCT ai.hadm_id) AS admission_count,
  AVG(ie.imaging_count) AS mean_imaging_count
FROM
  LOSGroup AS lg
INNER JOIN
  AdmissionInfo AS ai
  ON lg.hadm_id = ai.hadm_id
LEFT JOIN
  ImagingEvents AS ie
  ON lg.hadm_id = ie.hadm_id
GROUP BY
  lg.los_group,
  ai.admission_type
ORDER BY
  lg.los_group,
  ai.admission_type;