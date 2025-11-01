WITH first_trop AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_trop_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
    AND l.charttime IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),
ami_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS dx
    ON a.hadm_id = dx.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    LOWER(d_dx.long_title) LIKE '%acute myocardial infarction%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
)
SELECT
  COUNT(DISTINCT ami.subject_id) AS patient_count,
  COUNT(ami.hadm_id) AS admission_count,
  AVG(ami.anchor_age) AS mean_age,
  AVG(ami.los) AS mean_los,
  MIN(trop.first_trop_value) AS min_first_trop,
  MAX(trop.first_trop_value) AS max_first_trop,
  AVG(trop.first_trop_value) AS mean_first_trop,
  AVG(CAST(ami.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality
FROM
  ami_admissions AS ami
INNER JOIN
  first_trop AS trop
  ON ami.hadm_id = trop.hadm_id;