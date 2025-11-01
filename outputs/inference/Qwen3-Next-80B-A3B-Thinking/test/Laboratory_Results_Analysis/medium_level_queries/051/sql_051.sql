WITH acs_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

hs_tnt_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%High Sensitivity Troponin T%'
),

first_hstnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hs_tnt_item h ON l.itemid = h.itemid
  WHERE l.hadm_id IN (SELECT hadm_id FROM acs_admissions)
    AND l.valuenum IS NOT NULL
),

categorized AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN f.valuenum <= 14 THEN 'Normal'
      WHEN f.valuenum BETWEEN 15 AND 39 THEN 'Borderline'
      WHEN f.valuenum >= 40 THEN 'Myocardial Injury'
      ELSE NULL
    END AS category
  FROM acs_admissions a
  LEFT JOIN first_hstnt f ON a.hadm_id = f.hadm_id AND f.rn = 1
  WHERE f.valuenum IS NOT NULL
)

SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los
FROM categorized
WHERE category IS NOT NULL
GROUP BY category;