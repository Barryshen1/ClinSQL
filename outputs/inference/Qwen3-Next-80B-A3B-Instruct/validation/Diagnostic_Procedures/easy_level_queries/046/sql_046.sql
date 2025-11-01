WITH mech_support_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    pi.icd_code
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      LOWER(dip.long_title) LIKE '%intra-aortic balloon%'
      OR LOWER(dip.long_title) LIKE '%ventricular assist%'
      OR LOWER(dip.long_title) LIKE '%extracorporeal membrane oxygenation%'
      OR LOWER(dip.long_title) LIKE '%mechanical circulatory support%'
      OR LOWER(dip.long_title) LIKE '%ecmo%'
    )
),
patient_procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS num_distinct_procedures
  FROM mech_support_procedures
  GROUP BY subject_id
)
SELECT
  MAX(num_distinct_procedures) AS max_distinct_procedures_per_patient
FROM patient_procedure_counts;