WITH heart_rate_categories AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    CASE 
      WHEN AVG(ce.valuenum) < 60 THEN '<60'
      WHEN AVG(ce.valuenum) BETWEEN 60 AND 99 THEN '60-99'
      WHEN AVG(ce.valuenum) BETWEEN 100 AND 119 THEN '100-119'
      ELSE '>=120'
    END AS heart_rate_category,
    MAX(
      CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
          WHERE di.hadm_id = ie.hadm_id 
          AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410%') 
            OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
          )
        ) THEN 1 
        ELSE 0 
      END
    ) AS has_acute_mi
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.itemid = 220045  -- Heart rate itemid
    AND ce.valuenum IS NOT NULL
  GROUP BY ie.stay_id, ie.subject_id, ie.hadm_id
)
SELECT 
  heart_rate_category,
  COUNT(*) AS num_stays,
  ROUND(100.0 * SUM(has_acute_mi) / COUNT(*), 2) AS percent_with_acute_mi
FROM heart_rate_categories
GROUP BY heart_rate_category
ORDER BY 
  CASE heart_rate_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;