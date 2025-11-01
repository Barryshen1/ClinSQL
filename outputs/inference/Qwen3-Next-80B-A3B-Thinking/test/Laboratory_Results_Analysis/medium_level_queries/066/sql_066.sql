WITH chest_pain_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1
    AND di.long_title LIKE '%chest pain%'
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
hs_tnt_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-TnT%' OR label LIKE '%high sensitivity troponin%'
),
first_lab AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_tnt_item h ON l.itemid = h.itemid
  JOIN chest_pain_admissions c ON l.hadm_id = c.hadm_id
),
categorized AS (
  SELECT 
    CASE 
      WHEN valuenum < 14 THEN 'normal'
      WHEN valuenum >= 14 AND valuenum < 40 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category,
    valuenum
  FROM first_lab
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized), 2) AS percentage,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
   PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum)) AS iqr
FROM categorized
GROUP BY category;