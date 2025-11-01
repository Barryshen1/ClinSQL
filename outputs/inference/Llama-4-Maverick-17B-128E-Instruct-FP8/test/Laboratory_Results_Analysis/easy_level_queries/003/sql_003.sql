WITH 
troponin_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
acs_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 62 AND 66  
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 9 AND icd_code IN ('410.01', '410.11', '410.21', '410.31', '410.41', '410.51', '410.61', '410.71', '410.81', '410.91')
    OR icd_version = 10 AND icd_code LIKE 'I21%'
  )
),
peak_troponin AS (
  SELECT a.hadm_id, MAX(l.valuenum) AS peak_troponin
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  WHERE l.itemid IN (SELECT itemid FROM troponin_itemids) AND l.valuenum IS NOT NULL
  GROUP BY a.hadm_id
)
SELECT APPROX_QUANTILES(peak_troponin.peak_troponin, 100)[OFFSET(75)] AS percentile_75
FROM peak_troponin;