WITH acs_icd_codes AS (
  -- List of ICD codes for ACS (ICD-9 and ICD-10)
  SELECT '410' AS icd_prefix, 9 AS icd_version UNION ALL
  SELECT '4111', 9 UNION ALL
  SELECT 'I200', 10 UNION ALL
  SELECT 'I21', 10 UNION ALL
  SELECT 'I22', 10
),
acs_admissions AS (
  -- Find admissions for female patients age 50-60 with ACS diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    diag.icd_code,
    diag.icd_version,
    diag.seq_num
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    JOIN acs_icd_codes acs
      ON (
        (diag.icd_version = acs.icd_version)
        AND (
          -- For ICD-9, match prefix (first 3-4 digits)
          (diag.icd_version = 9 AND (LEFT(REPLACE(diag.icd_code, '.', ''), LENGTH(acs.icd_prefix)) = acs.icd_prefix))
          -- For ICD-10, match prefix (first 3-4 chars)
          OR (diag.icd_version = 10 AND (LEFT(REPLACE(diag.icd_code, '.', ''), LENGTH(acs.icd_prefix)) = acs.icd_prefix))
        )
      )
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
),
acs_admission_types AS (
  -- For each admission, determine if ACS is primary or secondary diagnosis
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN MIN(seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM acs_admissions
  GROUP BY subject_id, hadm_id
),
admission_los AS (
  -- Calculate LOS and stratify
  SELECT
    adm.subject_id,
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
),
acs_admissions_los AS (
  -- Combine ACS admissions with LOS and diagnosis type
  SELECT
    aat.subject_id,
    aat.hadm_id,
    aat.diagnosis_type,
    alos.los_days,
    CASE
      WHEN alos.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN alos.los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group
  FROM acs_admission_types aat
  JOIN admission_los alos
    ON aat.subject_id = alos.subject_id AND aat.hadm_id = alos.hadm_id
  WHERE alos.los_days BETWEEN 1 AND 8
),
diagnostic_procedure_counts AS (
  -- Count number of procedures per ACS admission
  SELECT
    aal.subject_id,
    aal.hadm_id,
    aal.diagnosis_type,
    aal.los_group,
    COUNT(DISTINCT proc.icd_code) AS num_procedures
  FROM acs_admissions_los aal
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON aal.subject_id = proc.subject_id AND aal.hadm_id = proc.hadm_id
  WHERE aal.los_group IS NOT NULL
  GROUP BY aal.subject_id, aal.hadm_id, aal.diagnosis_type, aal.los_group
)
SELECT
  los_group,
  diagnosis_type,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS p75
FROM diagnostic_procedure_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;