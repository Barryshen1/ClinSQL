WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
),
relevant_procedures AS (
  SELECT
    pa.hadm_id,
    di.long_title,
    pi.icd_code
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  ON
    pa.hadm_id = pi.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures di
  ON
    pi.icd_code = di.icd_code AND pi.icd_version = di.icd_version
  WHERE
    pi.icd_version = 10
    AND (
      (LOWER(di.long_title) LIKE '%ablation%' AND LOWER(di.long_title) LIKE '%catheter%')
      OR LOWER(di.long_title) LIKE '%cardioversion%'
    )
),
admission_procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM
    relevant_procedures
  GROUP BY
    hadm_id
)
SELECT
  STDDEV(distinct_procedure_count) AS sd_distinct_procedures
FROM
  admission_procedure_counts;