WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 41 AND 51
),
stroke_flag AS (
  SELECT 
    c.hadm_id,
    MAX(CASE 
          WHEN (d.icd_version = 9 AND SUBSTR(d.icd_code, 1, 3) IN ('430','431','432','433','434','436','437','438'))
            OR (d.icd_version = 10 AND SUBSTR(d.icd_code, 1, 2) = 'I6')
          THEN 1 
          ELSE 0 
        END) AS had_stroke
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),
map_measurements AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN ce.valuenum < 65 THEN '<65'
      WHEN ce.valuenum BETWEEN 65 AND 74 THEN '65-74'
      WHEN ce.valuenum BETWEEN 75 AND 84 THEN '75-84'
      WHEN ce.valuenum >= 85 THEN '>=85'
    END AS map_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON c.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 220179, 225312)
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg'
)
SELECT 
  map_category,
  COUNT(DISTINCT m.hadm_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN s.had_stroke = 1 THEN m.hadm_id ELSE NULL END) AS stroke_count,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN s.had_stroke = 1 THEN m.hadm_id ELSE NULL END),
    COUNT(DISTINCT m.hadm_id)
  ) AS stroke_rate
FROM map_measurements m
LEFT JOIN stroke_flag s 
  ON m.hadm_id = s.hadm_id
GROUP BY map_category
ORDER BY 
  CASE map_category
    WHEN '<65' THEN 1
    WHEN '65-74' THEN 2
    WHEN '75-84' THEN 3
    WHEN '>=85' THEN 4
  END;