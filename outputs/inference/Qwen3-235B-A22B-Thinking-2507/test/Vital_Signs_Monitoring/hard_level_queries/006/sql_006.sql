WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, p.anchor_age, p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          d.icd_code LIKE 'K25%' OR
          d.icd_code LIKE 'K26%' OR
          d.icd_code LIKE 'K27%' OR
          d.icd_code LIKE 'K28%' OR
          d.icd_code LIKE 'K290%' OR
          d.icd_code = 'K922'
        )
    )
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN cohort c
    ON i.subject_id = c.subject_id AND i.hadm_id = c.hadm_id
),
vital_signs AS (
  SELECT 
    i.stay_id,
    -- Heart rate > 100
    SUM(CASE WHEN itemid = 220045 AND valuenum > 100 THEN 1 ELSE 0 END) AS hr_abnormal,
    -- MAP < 65
    SUM(CASE WHEN itemid = 220052 AND valuenum < 65 THEN 1 ELSE 0 END) AS map_abnormal,
    -- Respiratory rate > 20
    SUM(CASE WHEN itemid = 220210 AND valuenum > 20 THEN 1 ELSE 0 END) AS rr_abnormal
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents c
  INNER JOIN icu_stays i
    ON c.stay_id = i.stay_id
  WHERE c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
    AND c.itemid IN (220045, 220052, 220210)
    AND c.valuenum IS NOT NULL
  GROUP BY i.stay_id
),
index_calc AS (
  SELECT 
    stay_id,
    hr_abnormal + map_abnormal + rr_abnormal AS instability_index
  FROM vital_signs
)
SELECT 
  APPROX_QUANTILES(instability_index, 100)[OFFSET(95)] AS percentile_95
FROM index_calc;