WITH target_patients AS (
  SELECT subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
circ_support_procs AS (
  SELECT p.subject_id,
         p.hadm_id,
         p.seq_num,
         d.long_title
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ventricular assist%'
     OR LOWER(d.long_title) LIKE '%intra-aortic balloon%'
     OR LOWER(d.long_title) LIKE '%extracorporeal circulation%'
     OR LOWER(d.long_title) LIKE '%mechanical circulatory%'
),
proc_counts AS (
  SELECT tp.subject_id,
         COUNT(DISTINCT c.seq_num) AS num_procedures
  FROM target_patients tp
  LEFT JOIN circ_support_procs c
    ON tp.subject_id = c.subject_id
  GROUP BY tp.subject_id
)
SELECT MIN(num_procedures) AS min_procedures_per_patient
FROM proc_counts;