WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 86 AND 96
),
matching_procedures AS (
  SELECT DISTINCT proc.subject_id, proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON proc.icd_code = d.icd_code
    AND proc.icd_version = d.icd_version
  WHERE (
    LOWER(d.long_title) LIKE '%ablation%'
    AND (
      LOWER(d.long_title) LIKE '%catheter%'
      OR LOWER(d.long_title) LIKE '%percutaneous%'
      OR LOWER(d.long_title) LIKE '%transcatheter%'
    )
  ) OR LOWER(d.long_title) LIKE '%cardioversion%'
),
procedure_counts AS (
  SELECT ep.subject_id, COUNT(mp.icd_code) AS num_distinct_procs
  FROM eligible_patients ep
  LEFT JOIN matching_procedures mp
    ON ep.subject_id = mp.subject_id
  GROUP BY ep.subject_id
)
SELECT STDDEV(num_distinct_procs) AS standard_deviation
FROM procedure_counts;