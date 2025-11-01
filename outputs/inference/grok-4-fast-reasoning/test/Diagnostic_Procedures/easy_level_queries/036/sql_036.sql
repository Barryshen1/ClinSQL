WITH qualifying_procs AS (
  SELECT DISTINCT
    p.subject_id,
    dip.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.subject_id = pi.subject_id AND a.hadm_id = pi.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 42 AND 52
    AND LOWER(dip.long_title) LIKE '%valve%'
    AND (LOWER(dip.long_title) LIKE '%repair%'
         OR LOWER(dip.long_title) LIKE '%replacement%'
         OR LOWER(dip.long_title) LIKE '%replace%')
)
SELECT
  AVG(distinct_count) AS avg_distinct_valve_procedures_per_patient
FROM (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_count
  FROM qualifying_procs
  GROUP BY subject_id
);