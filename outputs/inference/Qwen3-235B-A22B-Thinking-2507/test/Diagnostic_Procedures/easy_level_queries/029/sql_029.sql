WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
),
pacemaker_procedures AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.chartdate,
    (pat.anchor_age + (EXTRACT(YEAR FROM p.chartdate) - pat.anchor_year)) AS age_at_procedure
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age IS NOT NULL
    AND pat.anchor_year IS NOT NULL
    AND p.chartdate IS NOT NULL
    AND (
      LOWER(d.long_title) LIKE '%pacemaker%'
      OR LOWER(d.long_title) LIKE '%defibrillator%'
      OR LOWER(d.long_title) LIKE '%implantable cardioverter%'
      OR LOWER(d.long_title) LIKE '%icd%'
    )
),
filtered_procedures AS (
  SELECT 
    subject_id,
    COUNT(*) AS procedure_count
  FROM pacemaker_procedures
  WHERE age_at_procedure BETWEEN 78 AND 88
  GROUP BY subject_id
),
patient_counts AS (
  SELECT 
    ep.subject_id,
    COALESCE(fp.procedure_count, 0) AS procedure_count
  FROM eligible_patients ep
  LEFT JOIN filtered_procedures fp
    ON ep.subject_id = fp.subject_id
)
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY procedure_count) AS p25_procedure_count
FROM patient_counts;