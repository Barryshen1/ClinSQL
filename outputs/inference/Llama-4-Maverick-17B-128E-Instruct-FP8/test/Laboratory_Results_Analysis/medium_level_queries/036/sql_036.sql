WITH patients_ami AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 77 AND 87
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code LIKE 'I21%'
  )
),
hs_tnt AS (
  SELECT pa.hadm_id, le.valuenum, ROW_NUMBER() OVER (PARTITION BY pa.hadm_id ORDER BY le.charttime) as rn
  FROM patients_ami pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON pa.hadm_id = le.hadm_id
  WHERE le.itemid = (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%Troponin T%' AND label LIKE '%High Sensitivity%')
),
hs_tnt_category AS (
  SELECT hadm_id, valuenum,
  CASE
    WHEN valuenum < 14 THEN 'Normal'
    WHEN valuenum BETWEEN 14 AND 52 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS category
  FROM hs_tnt
  WHERE rn = 1
)
SELECT category, COUNT(*) as count, COUNT(*) * 100.0 / (SELECT COUNT(*) FROM hs_tnt_category) as percentage
FROM hs_tnt_category
GROUP BY category;