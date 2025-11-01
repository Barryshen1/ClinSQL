WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
coronary_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT p.icd_code) AS num_coronary_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN cohort c ON p.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    -- ICD-9 codes for coronary angiography/PCI
    (
      p.icd_code IN ('88.55', '36.06', '36.07', '36.09')
      OR LOWER(d.long_title) LIKE '%coronary angiography%'
      OR LOWER(d.long_title) LIKE '%coronary arteriography%'
      OR LOWER(d.long_title) LIKE '%percutaneous coronary intervention%'
      OR LOWER(d.long_title) LIKE '%ptca%'
      OR LOWER(d.long_title) LIKE '%angioplasty%'
      OR LOWER(d.long_title) LIKE '%stent%'
    )
  GROUP BY p.subject_id, p.hadm_id
)
SELECT
  APPROX_QUANTILES(num_coronary_procs, 4)[OFFSET(3)] AS percentile_75
FROM coronary_procedures;