WITH proc_patients AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT CONCAT(proc.icd_code, '-', proc.icd_version)) AS distinct_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      dicd.long_title LIKE '%pacemaker%' 
      OR dicd.long_title LIKE '%implantable cardioverter defibrillator%'
      OR dicd.long_title LIKE '%ICD%'
    )
  GROUP BY p.subject_id
)
SELECT 
  APPROX_QUANTILES(distinct_proc_count, 100)[OFFSET(25)] AS percentile_25
FROM proc_patients;