WITH cohort AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    p.anchor_age,
    p.anchor_year,
    i.intime,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 40 AND 50
),

mi_diagnosis AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '410%') OR 
           (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
      THEN 1 ELSE 0 
    END) AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

sbp_mean AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS mean_sbp
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220050
    AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL '48' HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
)

SELECT 
  sbp_category,
  COUNT(*) AS total_in_category,
  SUM(has_mi) AS mi_count,
  (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()) AS percent_in_category,
  (SUM(has_mi) * 100.0 / COUNT(*)) AS mi_rate
FROM (
  SELECT 
    c.stay_id,
    CASE 
      WHEN sbp.mean_sbp < 140 THEN '<140'
      WHEN sbp.mean_sbp >= 140 AND sbp.mean_sbp <= 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    COALESCE(mi.has_mi, 0) AS has_mi
  FROM cohort c
  LEFT JOIN sbp_mean sbp ON c.stay_id = sbp.stay_id
  LEFT JOIN mi_diagnosis mi ON c.hadm_id = mi.hadm_id
  WHERE sbp.mean_sbp IS NOT NULL
) AS categorized
GROUP BY sbp_category;