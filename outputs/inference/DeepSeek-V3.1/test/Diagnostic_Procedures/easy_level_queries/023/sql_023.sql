WITH cohort AS (
  SELECT 
      adm.subject_id, 
      adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
      AND pat.anchor_age BETWEEN 82 AND 92
),
cardiac_procedures AS (
  SELECT 
      proc.hadm_id,
      proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
      ON proc.icd_code = dicd.icd_code 
      AND proc.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%cardiac%'
      OR LOWER(dicd.long_title) LIKE '%heart%'
      OR LOWER(dicd.long_title) LIKE '%coronary%'
      OR LOWER(dicd.long_title) LIKE '%pacemaker%'
      OR LOWER(dicd.long_title) LIKE '%defibrillator%'
      OR LOWER(dicd.long_title) LIKE '%catheterization%'
      OR LOWER(dicd.long_title) LIKE '%echocardiography%'
),
proc_counts AS (
  SELECT 
      c.hadm_id,
      COUNT(DISTINCT cp.icd_code) AS distinct_cardiac_procedures
  FROM cohort c
  LEFT JOIN cardiac_procedures cp
      ON c.hadm_id = cp.hadm_id
  GROUP BY c.hadm_id
)
SELECT 
    APPROX_QUANTILES(distinct_cardiac_procedures, 100)[OFFSET(25)] AS percentile_25
FROM proc_counts;