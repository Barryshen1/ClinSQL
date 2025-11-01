WITH target_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 41 AND 51
),

rr_measurements AS (
  SELECT
    tp.stay_id,
    c.valuenum
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON tp.stay_id = c.stay_id
  WHERE c.itemid = 618
    AND c.charttime BETWEEN tp.intime AND tp.intime + INTERVAL 48 HOUR
    AND c.valuenum IS NOT NULL
),

rr_avg AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM rr_measurements
  GROUP BY stay_id
),

categorized AS (
  SELECT
    stay_id,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '>=30'
      ELSE NULL
    END AS rr_category
  FROM rr_avg
),

stroke_diagnosis AS (
  SELECT
    tp.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = tp.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
        )
    ) THEN 1 ELSE 0 END AS has_stroke
  FROM target_patients tp
)

SELECT
  c.rr_category,
  COUNT(*) AS count,
  AVG(s.has_stroke) AS stroke_rate
FROM categorized c
JOIN target_patients tp ON c.stay_id = tp.stay_id
JOIN stroke_diagnosis s ON tp.hadm_id = s.hadm_id
GROUP BY c.rr_category;