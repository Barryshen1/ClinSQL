WITH cabg_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%coronary%'
    AND LOWER(long_title) LIKE '%bypass%'
    AND icd_version IN (9, 10)
),
patients_with_age AS (
  SELECT
    p.subject_id,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 45 AND 55
),
cabg_admissions AS (
  SELECT DISTINCT
    pwa.subject_id,
    a.hadm_id
  FROM patients_with_age pwa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pwa.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.hadm_id = pi.hadm_id
  INNER JOIN cabg_codes cc
    ON pi.icd_code = cc.icd_code AND pi.icd_version = cc.icd_version
),
cabg_counts AS (
  SELECT
    pwa.subject_id,
    COUNT(DISTINCT ca.hadm_id) AS cabg_procedure_count
  FROM patients_with_age pwa
  LEFT JOIN cabg_admissions ca
    ON pwa.subject_id = ca.subject_id
  GROUP BY pwa.subject_id
)
SELECT
  PERCENTILE_CONT(cabg_procedure_count, 0.25) OVER() AS percentile_25
FROM cabg_counts
LIMIT 1;