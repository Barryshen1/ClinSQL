WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
coronary_procedures AS (
  SELECT 'angioplasty' AS keyword
  UNION ALL SELECT 'stent'
  UNION ALL SELECT 'percutaneous coronary'
  UNION ALL SELECT 'PCI'
),
procedure_codes AS (
  SELECT DISTINCT d_icd.icd_code, d_icd.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d_icd
  CROSS JOIN coronary_procedures cp
  WHERE LOWER(d_icd.long_title) LIKE '%' || LOWER(cp.keyword) || '%'
    AND d_icd.long_title NOT LIKE '%Vein%' -- Exclude venous procedures if possible
    AND d_icd.long_title NOT LIKE '%Bypass%' -- Not CABG
),
procedures_in_range AS (
  SELECT adm.hadm_id, COUNT(*) AS procedure_count
  FROM filtered_patients fp
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm ON fp.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc ON adm.hadm_id = proc.hadm_id
  JOIN procedure_codes pc ON proc.icd_code = pc.icd_code AND proc.icd_version = pc.icd_version
  GROUP BY adm.hadm_id
)
SELECT
  APPROX_QUANTILES(procedure_count, 1000)[OFFSET(750)] AS percentile_75
FROM procedures_in_range;