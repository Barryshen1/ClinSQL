WITH male_patients_82_92 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 82 AND 92
),
pacemaker_icd_procedures AS (
  SELECT p.subject_id, a.hadm_id, pr.icd_code
  FROM male_patients_82_92 p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%pacemaker%'
     OR LOWER(dpr.long_title) LIKE '%cardioverter%'
     OR LOWER(dpr.long_title) LIKE '%defibrillator%'
     OR LOWER(dpr.long_title) LIKE '%icd%'
     OR LOWER(dpr.long_title) LIKE '%implant%'
)
, procedure_counts AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS num_distinct_implant_procs
  FROM pacemaker_icd_procedures
  GROUP BY hadm_id
)
SELECT
  MIN(num_distinct_implant_procs) AS min_distinct_implant_procs_per_hospitalization
FROM procedure_counts;