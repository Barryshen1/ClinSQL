WITH coronary_per_hadm AS (
  SELECT
    adm.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS coronary_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON proc.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON proc.icd_code = d.icd_code
   AND proc.icd_version = d.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND LOWER(d.long_title) LIKE '%coronary%'
    AND (LOWER(d.long_title) LIKE '%angiography%' OR LOWER(d.long_title) LIKE '%angioplasty%')
    -- ensure the procedure occurred during the admission
    AND DATE(adm.admittime) <= proc.chartdate
    AND proc.chartdate <= DATE(adm.dischtime)
  GROUP BY adm.hadm_id
  HAVING COUNT(DISTINCT proc.icd_code) > 0
)
SELECT
  -- 75th percentile across admissions
  CAST(APPROX_QUANTILES(coronary_count, 100)[OFFSET(75)] AS FLOAT64) AS percentile_75
FROM coronary_per_hadm;