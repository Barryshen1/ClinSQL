WITH stroke_adms AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (
      icd_code LIKE '430%' OR
      icd_code LIKE '431%' OR
      icd_code LIKE '432%' OR
      icd_code LIKE '433%' OR
      icd_code LIKE '434%' OR
      icd_code = '436'
    )) OR
    (icd_version = 10 AND icd_code LIKE 'I6[0-4]%')
  )
)
SELECT
  APPROX_QUANTILES(stays.los / 24.0, 100)[OFFSET(50)] AS median_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` stays
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON stays.subject_id = pat.subject_id
INNER JOIN stroke_adms sa
  ON stays.subject_id = sa.subject_id
  AND stays.hadm_id = sa.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 35 AND 45;