WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 43 AND 53
),
mech_support_procs AS (
  SELECT p.subject_id, proc.icd_code
  FROM female_patients p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
   AND proc.icd_version = dproc.icd_version
  WHERE LOWER(dproc.long_title) LIKE '%mechanical circulatory support%'
     OR LOWER(dproc.long_title) LIKE '%extracorporeal membrane oxygenation%'
     OR LOWER(dproc.long_title) LIKE '%ventricular assist device%'
     OR LOWER(dproc.long_title) LIKE '%intra-aortic balloon pump%'
),
counts_per_patient AS (
  SELECT subject_id,
         COUNT(DISTINCT icd_code) AS distinct_support_procs
  FROM mech_support_procs
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(distinct_support_procs, 100)[OFFSET(25)] AS percentile_25th
FROM counts_per_patient;