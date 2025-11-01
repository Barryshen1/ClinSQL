WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    )
),
troponin_t AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label = 'Troponin T'
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_t t 
    ON l.itemid = t.itemid
  INNER JOIN eligible_admissions e
    ON l.hadm_id = e.hadm_id
  WHERE l.valuenum IS NOT NULL
    AND l.charttime >= e.admittime
    AND l.charttime <= e.dischtime
),
combined AS (
  SELECT 
    e.hadm_id,
    e.subject_id,
    e.age_at_admission,
    e.admittime,
    e.dischtime,
    t.valuenum,
    CASE 
      WHEN t.valuenum < 14 THEN 'normal'
      WHEN t.valuenum >= 14 AND t.valuenum < 30 THEN 'borderline'
      WHEN t.valuenum >= 30 THEN 'elevated'
    END AS category,
    TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / (24*60*60) AS los_days
  FROM eligible_admissions e
  INNER JOIN first_troponin t 
    ON e.hadm_id = t.hadm_id
  WHERE t.rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
  AVG(los_days) AS mean_los_days
FROM combined
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;