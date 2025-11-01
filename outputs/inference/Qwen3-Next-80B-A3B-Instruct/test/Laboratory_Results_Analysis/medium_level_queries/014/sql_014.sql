WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id, a.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND (
      LOWER(d_icd.long_title) LIKE '%acute coronary syndrome%'
      OR LOWER(d_icd.long_title) LIKE '%acute myocardial infarction%'
      OR d.icd_code LIKE 'I21%'
      OR d.icd_code LIKE 'I24%'
    )
    AND d.icd_version = 10
),
first_troponin_t AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d ON l.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum >= 0
)
SELECT
  SUM(CASE WHEN f.valuenum < 0.04 THEN 1 ELSE 0 END) AS normal_count,
  SUM(CASE WHEN f.valuenum >= 0.04 AND f.valuenum < 0.10 THEN 1 ELSE 0 END) AS borderline_count,
  SUM(CASE WHEN f.valuenum >= 0.10 THEN 1 ELSE 0 END) AS elevated_count,
  COUNT(*) AS total_count,
  ROUND(100.0 * SUM(CASE WHEN f.valuenum < 0.04 THEN 1 ELSE 0 END) / COUNT(*), 2) AS normal_percentage,
  ROUND(100.0 * SUM(CASE WHEN f.valuenum >= 0.04 AND f.valuenum < 0.10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS borderline_percentage,
  ROUND(100.0 * SUM(CASE WHEN f.valuenum >= 0.10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS elevated_percentage
FROM acs_admissions a
INNER JOIN first_troponin_t f ON a.hadm_id = f.hadm_id
WHERE f.rn = 1;