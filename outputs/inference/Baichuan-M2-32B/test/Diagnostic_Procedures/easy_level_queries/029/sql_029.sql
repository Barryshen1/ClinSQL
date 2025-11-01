WITH patient_age AS (
  SELECT 
    subject_id,
    DATE(anchor_year - anchor_age, 1, 1) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_year IS NOT NULL
    AND anchor_age IS NOT NULL
),
pacemaker_procedures AS (
  SELECT 
    pr.subject_id,
    pr.icd_code,
    pr.chartdate
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code AND pr.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%pacemaker%' 
    OR LOWER(d.long_title) LIKE '%icd%'
    OR LOWER(d.long_title) LIKE '%implantable cardioverter%'
),
patient_procedures_with_age AS (
  SELECT 
    pa.subject_id,
    pp.icd_code,
    pp.chartdate,
    DATE_DIFF(pp.chartdate, pa.birth_date, YEAR) AS age_at_procedure
  FROM pacemaker_procedures pp
  JOIN patient_age pa ON pp.subject_id = pa.subject_id
),
patient_procedures_filtered AS (
  SELECT *
  FROM patient_procedures_with_age
  WHERE age_at_procedure BETWEEN 78 AND 88
),
patient_counts AS (
  SELECT 
    pa.subject_id,
    COUNT(DISTINCT ppf.icd_code) AS distinct_procedure_count
  FROM patient_age pa
  LEFT JOIN patient_procedures_filtered ppf ON pa.subject_id = ppf.subject_id
  GROUP BY pa.subject_id
)
SELECT 
  APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(25)] AS p25
FROM patient_counts;