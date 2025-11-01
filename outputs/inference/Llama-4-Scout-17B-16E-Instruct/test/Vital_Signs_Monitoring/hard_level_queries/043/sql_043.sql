WITH 
  -- Define population: Male patients aged 40-50 with respiratory failure
  population AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      p.stay_id,
      p.intime,
      p.first_careunit,
      a.admittime,
      EXTRACT(DAY FROM p.intime - a.admittime) AS admission_to_icu_days,
      CASE 
        WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_icu`.diagnoses_icd di 
          WHERE di.hadm_id = p.hadm_id 
          AND di.icd_code LIKE 'J%' 
          AND di.icd_code NOT IN ('J00', 'J01', 'J02', 'J03', 'J04', 'J05', 'J06', 'J07', 'J08', 
                                 'J20', 'J21', 'J22', 'J23', 'J24', 'J25', 'J26', 'J27', 'J28', 
                                 'J30', 'J31', 'J32', 'J33', 'J34', 'J35', 'J36', 'J37', 'J38', 
                                 'J39', 'J40', 'J41', 'J42', 'J43', 'J44', 'J45', 'J46', 'J47', 
                                 'J48', 'J49', 'J50', 'J51', 'J52', 'J53', 'J54', 'J55', 'J56', 
                                 'J57', 'J58', 'J59', 'J60', 'J61', 'J62', 'J63', 'J64', 'J65', 
                                 'J66', 'J67', 'J68', 'J69', 'J70', 'J71', 'J72', 'J73', 'J74', 
                                 'J75', 'J76', 'J77', 'J78', 'J79', 'J80', 'J81', 'J82', 'J83', 
                                 'J84', 'J85', 'J86', 'J87', 'J88', 'J89', 'J90', 'J91', 'J92', 
                                 'J93', 'J94', 'J95', 'J96', 'J97', 'J98', 'J99')
        ) THEN 1 
        ELSE 0 
      END AS has_respiratory_failure
    FROM 
      `physionet-data.mimiciv_3_1_icu`.icustays p
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp`.admissions a 
      ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
    WHERE 
      p.first_careunit LIKE '%ICU%' 
      AND a.gender = 'M' 
      AND EXTRACT(YEAR FROM a.admittime) - a.anchor_year BETWEEN 40 AND 50
  ),
  
  -- Assume vii calculation is available or defined in a similar manner
  vii_calculation AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      -- Example calculation, replace with actual vii calculation
      (RANDOM() * 10) AS vii
    FROM 
      population
    WHERE 
      has_respiratory_failure = 1 
      AND admission_to_icu_days <= 2
  )

SELECT 
  PERCENTILE_CONT(0.25)(vii) OVER () AS p25,
  PERCENTILE_CONT(0.5)(vii) OVER () AS p50,
  PERCENTILE_CONT(0.75)(vii) OVER () AS p75,
  PERCENTILE_CONT(0.95)(vii) OVER () AS p95,
  STDDEV(vii) AS sd
FROM 
  vii_calculation;