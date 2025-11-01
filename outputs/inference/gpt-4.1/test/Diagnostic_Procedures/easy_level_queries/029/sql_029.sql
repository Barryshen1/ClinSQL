WITH male_aged_78_88 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 78 AND 88
),
pacemaker_icd_procs AS (
  SELECT p.subject_id, proc.icd_code
  FROM male_aged_78_88 p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%pacemaker%'
     OR LOWER(dproc.long_title) LIKE '%defibrillator%'
     OR LOWER(dproc.long_title) LIKE '%icd%'
     OR LOWER(dproc.long_title) LIKE '%cardioverter%'
     OR LOWER(dproc.long_title) LIKE '%implantable%'
),
per_patient_counts AS (
  SELECT subject_id, COUNT(DISTINCT icd_code) AS num_distinct_pacemaker_icd_procs
  FROM pacemaker_icd_procs
  GROUP BY subject_id
)
SELECT
  PERCENTILE_CONT(num_distinct_pacemaker_icd_procs, 0.25) OVER() AS pacemaker_icd_proc_25th_percentile
FROM per_patient_counts;