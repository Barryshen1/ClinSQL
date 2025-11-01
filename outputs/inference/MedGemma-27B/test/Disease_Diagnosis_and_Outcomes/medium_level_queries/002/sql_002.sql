WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.deathtime,
    a.dischtime,
    a.admittime, -- Added admittime here
    a.admission_type,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 62 AND 72
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_version = 10
), CKD AS (
  SELECT
    di.subject_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code LIKE 'N18%' OR di.icd_code LIKE 'I12%'
), Diabetes AS (
  SELECT
    di.subject_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E10%'
), AMI AS (
  SELECT
    di.subject_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code LIKE 'I21%'
), Shock AS (
  SELECT
    di.subject_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code LIKE 'R57%'
), RespiratoryFailure AS (
  SELECT
    di.subject_id
  FROM DiagnosisInfo AS di
  WHERE
    di.icd_code LIKE 'J96%'
), Mortality AS (
  SELECT
    pi.subject_id,
    CASE
      WHEN pi.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality,
    -- Calculate LOS using TIMESTAMP_DIFF
    TIMESTAMP_DIFF(pi.dischtime, pi.admittime, DAY) AS los
  FROM PatientInfo AS pi
), FinalData AS (
  SELECT
    m.subject_id,
    m.mortality,
    m.los,
    CASE
      WHEN c.subject_id IS NOT NULL THEN 1
      ELSE 0
    END AS ckd,
    CASE
      WHEN d.subject_id IS NOT NULL THEN 1
      ELSE 0
    END AS diabetes
  FROM Mortality AS m
  LEFT JOIN CKD AS c
    ON m.subject_id = c.subject_id
  LEFT JOIN Diabetes AS d
    ON m.subject_id = d.subject_id
  WHERE
    m.subject_id IN (SELECT subject_id FROM AMI)
    AND m.subject_id NOT IN (SELECT subject_id FROM Shock)
    AND m.subject_id NOT IN (SELECT subject_id FROM RespiratoryFailure)
)
SELECT
  CASE
    WHEN los <= 5 THEN '≤5 days'
    ELSE '>5 days'
  END AS los_group,
  COUNT(subject_id) AS total_patients,
  SUM(mortality) AS mortality_count,
  AVG(mortality) AS mortality_rate,
  SUM(ckd) / COUNT(subject_id) AS ckd_prevalence,
  SUM(diabetes) / COUNT(subject_id) AS diabetes_prevalence
FROM FinalData
GROUP BY
  los_group
ORDER BY
  los_group;