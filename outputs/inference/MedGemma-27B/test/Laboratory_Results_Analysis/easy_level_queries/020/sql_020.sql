WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'M' AND anchor_age = 49
), HospitalizationInfo AS (
  SELECT
    hadm_id
  FROM admissions
  WHERE
    subject_id IN (
      SELECT
        subject_id
      FROM PatientInfo
    )
), DiagnosisInfo AS (
  SELECT DISTINCT
    hadm_id
  FROM diagnoses_icd
  WHERE
    icd_code IN ('398.11', '398.12', '398.13', '398.14', '398.15', '398.16', '398.19', '398.21', '398.22', '398.23', '398.24', '398.25', '398.26', '398.29', '398.31', '398.32', '398.33', '398.34', '398.35', '398.36', '398.39', '398.41', '398.42', '398.43', '398.44', '398.45', '398.46', '398.49', '398.51', '398.52', '398.53', '398.54', '398.55', '398.56', '398.59', '398.61', '398.62', '398.63', '398.64', '398.65', '398.66', '398.69', '398.9', '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.5', 'I50.6', 'I50.9')
), HemoglobinEvents AS (
  SELECT
    h.hadm_id,
    l.charttime,
    l.valuenum AS hemoglobin_value
  FROM labevents AS l
  JOIN d_labitems AS d
    ON l.itemid = d.itemid
  JOIN admissions AS h
    ON l.hadm_id = h.hadm_id
  WHERE
    d.label = 'Hemoglobin' AND l.valuenum IS NOT NULL
), NadirHemoglobin AS (
  SELECT
    hadm_id,
    MIN(hemoglobin_value) AS nadir_hemoglobin
  FROM HemoglobinEvents
  GROUP BY
    hadm_id
)
SELECT
  PERCENTILE_CONT(0.75, nadir_hemoglobin)
FROM NadirHemoglobin
WHERE
  hadm_id IN (
    SELECT
      hadm_id
    FROM HospitalizationInfo
    INTERSECT
    SELECT
      hadm_id
    FROM DiagnosisInfo
  );