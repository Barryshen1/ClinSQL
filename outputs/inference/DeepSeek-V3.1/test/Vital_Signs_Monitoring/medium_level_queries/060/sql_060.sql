WITH sbp_first_24h AS (
  SELECT 
    ie.stay_id,
    ie.hadm_id,
    MAX(CASE 
          WHEN ce.valuenum < 130 THEN '<130'
          WHEN ce.valuenum BETWEEN 130 AND 139 THEN '130-139'
          WHEN ce.valuenum BETWEEN 140 AND 159 THEN '140-159'
          WHEN ce.valuenum >= 160 THEN '>=160'
        END) AS sbp_category
  FROM `physionet-data.mimiciv_3_1_icu`.icustays ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON ie.stay_id = ce.stay_id
      AND ce.charttime >= ie.intime
      AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
      AND ce.itemid IN (220179, 220050)  -- SBP items
      AND ce.valuenum > 0  -- valid numeric value
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
  GROUP BY ie.stay_id, ie.hadm_id
),
stroke_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_code LIKE 'I63%'   -- cerebral infarction
     OR icd_code LIKE 'I61%'   -- intracerebral hemorrhage
     OR icd_code LIKE 'I62%'   -- other nontraumatic intracranial hemorrhage
)
SELECT 
  sbp_category,
  COUNT(*) AS total_stays,
  COUNTIF(sp.hadm_id IS NOT NULL) AS stroke_stays,
  ROUND(COUNTIF(sp.hadm_id IS NOT NULL) * 100.0 / COUNT(*), 2) AS stroke_rate_percent
FROM sbp_first_24h s
LEFT JOIN stroke_patients sp
  ON s.hadm_id = sp.hadm_id
GROUP BY sbp_category
ORDER BY sbp_category;