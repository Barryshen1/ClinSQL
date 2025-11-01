WITH chest_pain_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    LOWER(di.long_title) LIKE '%chest pain%' 
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
),
lab_events AS (
  SELECT 
    a.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM chest_pain_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  WHERE 
    (LOWER(di.label) LIKE '%hs-tnt%' OR LOWER(di.label) LIKE '%high sensitivity troponin%')
    AND l.charttime >= a.admittime
    AND l.valuenum IS NOT NULL
)
SELECT 
  category,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage
FROM (
  SELECT 
    CASE 
      WHEN valuenum <= 14 THEN 'normal'
      WHEN valuenum > 14 AND valuenum <= 20 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category
  FROM lab_events
  WHERE rn = 1
)
GROUP BY category;