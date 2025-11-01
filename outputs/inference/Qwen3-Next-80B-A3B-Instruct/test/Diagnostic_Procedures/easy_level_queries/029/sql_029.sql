WITH pacemaker_icd_procedures AS (
  SELECT DISTINCT
    p.subject_id,
    pi.icd_code,
    pi.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON p.subject_id = pi.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code
    AND pi.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      LOWER(dip.long_title) LIKE '%pacemaker%'
      OR LOWER(dip.long_title) LIKE '%icd%'
      OR LOWER(dip.long_title) LIKE '%implantable cardioverter defibrillator%'
      OR LOWER(dip.long_title) LIKE '%defibrillator%'
      OR LOWER(dip.long_title) LIKE '%cardiac resynchronization therapy%'
    )
),
patient_procedure_counts AS (
  SELECT
    subject_id,
    COUNT(*) AS procedure_count
  FROM pacemaker_icd_procedures
  GROUP BY subject_id
)
SELECT
  PERCENTILE_CONT(procedure_count, 0.25) OVER () AS p25_procedure_count
FROM patient_procedure_counts
LIMIT 1;