WITH chest_pain_admissions AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    p.anchor_age, 
    p.anchor_year, 
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE 
    d.seq_num = 1
    AND LOWER(d_icd.long_title) LIKE '%chest pain%'
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
),

hs_tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%hs-tn t%' OR LOWER(label) LIKE '%high sensitivity troponin t%'
),

first_hs_tnt AS (
  SELECT 
    l.hadm_id, 
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_tnt_items h 
    ON l.itemid = h.itemid
  WHERE 
    l.hadm_id IN (SELECT hadm_id FROM chest_pain_admissions)
    AND l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),

categorized_data AS (
  SELECT 
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal'
      WHEN valuenum > 0.04 AND valuenum <= 0.1 THEN 'Borderline'
      WHEN valuenum > 0.1 THEN 'Injury'
      ELSE 'Unknown'
    END AS category,
    valuenum
  FROM first_hs_tnt
)

SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
   PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum)) AS iqr
FROM categorized_data
GROUP BY category;