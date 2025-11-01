WITH echocardiography_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiography%'
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 84 AND 94
),
procedure_counts AS (
  SELECT hadm_id, COUNT(DISTINCT p.icd_code) AS distinct_echoprocs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  JOIN echocardiography_codes ec
    ON p.icd_code = ec.icd_code AND p.icd_version = ec.icd_version
  GROUP BY hadm_id
)
SELECT APPROX_QUANTILES(distinct_echoprocs, 100)[OFFSET(25)] AS percentile_25
FROM procedure_counts;