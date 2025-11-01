WITH PatientHF AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 39 AND 49
  INTERSECT
  SELECT
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%heart failure%'
),
ComorbidityScore AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientHF
    )
    AND d.icd_code IN ('I10', 'I11', 'I12', 'I13', 'I15', 'I50', 'E11', 'E13', 'E14') -- CKD and Diabetes codes
  GROUP BY
    a.subject_id,
    a.hadm_id
),
ComorbidityTertiles AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN comorbidity_count <= 1
      THEN 'Low'
      WHEN comorbidity_count <= 2
      THEN 'Med'
      ELSE 'High'
    END AS comorbidity_tertile
  FROM
    ComorbidityScore
),
PatientData AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime,
    ct.comorbidity_tertile
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    ComorbidityTertiles AS ct
    ON a.subject_id = ct.subject_id AND a.hadm_id = ct.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientHF
    )
),
LOSCalculation AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    comorbidity_tertile,
    TIMESTAMP_DIFF(dischtime, admitime, DAY) AS los
  FROM
    PatientData
)
SELECT
  comorbidity_tertile,
  CASE
    WHEN los <= 5
    THEN '≤5'
    ELSE '>5'
  END AS los_category,
  COUNT(subject_id) AS N,
  SUM(hospital_expire_flag) AS mortality_count,
  SUM(hospital_expire_flag) * 1.0 / COUNT(subject_id) AS mortality_percentage
FROM
  LOSCalculation
GROUP BY
  comorbidity_tertile,
  los_category
ORDER BY
  comorbidity_tertile,
  los_category;