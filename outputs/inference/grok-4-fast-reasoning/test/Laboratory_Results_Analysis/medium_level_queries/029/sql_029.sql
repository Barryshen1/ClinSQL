WITH qualifying_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '7865%'))
    OR
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'R07%'))
  )
),
qualifying_troponin AS (
  SELECT DISTINCT hadm_id
  FROM (
    SELECT 
      hadm_id,
      FIRST_VALUE(valuenum) OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS initial_troponin
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON l.itemid = li.itemid
    WHERE LOWER(li.label) LIKE '%troponin t%'
      AND l.valueuom = 'ng/mL'
      AND l.valuenum IS NOT NULL
      AND l.hadm_id IS NOT NULL
  ) sub
  WHERE initial_troponin > 0.04
),
qualifying_hadm AS (
  SELECT hadm_id FROM qualifying_diagnoses
  INTERSECT DISTINCT
  SELECT hadm_id FROM qualifying_troponin
)
SELECT 
  COUNT(*) AS num_admissions,
  SUM(CAST(hospital_expire_flag AS INT64)) AS num_deaths,
  ROUND(100.0 * SUM(CAST(hospital_expire_flag AS INT64)) / COUNT(*), 2) AS mortality_rate_percent
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
JOIN qualifying_hadm q
  ON a.hadm_id = q.hadm_id
WHERE p.gender = 'M'
  AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 58 AND 68;