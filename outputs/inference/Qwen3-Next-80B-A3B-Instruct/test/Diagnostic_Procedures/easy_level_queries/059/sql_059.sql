WITH cardiac_procedures AS (
  SELECT DISTINCT
    pi.hadm_id,
    pi.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pi.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND REGEXP_CONTAINS(LOWER(dip.long_title), r'cardiac|heart|coronary|bypass|valve|angioplasty|stent|revascularization|pacemaker|defibrillator|echocardiogram|cardiopulmonary')
),
procedures_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_cardiac_procedures
  FROM cardiac_procedures
  GROUP BY hadm_id
)
SELECT
  PERCENTILE_CONT(num_cardiac_procedures, 0.75) - PERCENTILE_CONT(num_cardiac_procedures, 0.25) AS iqr
FROM procedures_per_hadm;