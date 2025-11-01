WITH male_patients_63_73 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
),
cardiac_procedures AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    -- ICD-9 cardiac procedures: 35*, 36*, 37*, 88*
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^35') OR
      REGEXP_CONTAINS(icd_code, r'^36') OR
      REGEXP_CONTAINS(icd_code, r'^37') OR
      REGEXP_CONTAINS(icd_code, r'^88')
    ))
    -- Add ICD-10 cardiac procedures if needed (not common in MIMIC-IV, but can be extended)
),
cardiac_procs_per_hadm AS (
  SELECT
    p.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_cardiac_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN male_patients_63_73 p
    ON proc.subject_id = p.subject_id
  INNER JOIN cardiac_procedures cp
    ON proc.icd_code = cp.icd_code AND proc.icd_version = cp.icd_version
  GROUP BY p.subject_id, proc.hadm_id
)
SELECT
  quantiles[OFFSET(2)] AS cardiac_procedure_75th_percentile
FROM (
  SELECT
    APPROX_QUANTILES(num_cardiac_procs, 4) AS quantiles
  FROM cardiac_procs_per_hadm
);