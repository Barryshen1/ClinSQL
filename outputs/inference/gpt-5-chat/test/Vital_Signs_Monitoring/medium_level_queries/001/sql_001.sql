WITH sysbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(category) LIKE '%blood pressure%'
),
first_24h_sbp AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  JOIN sysbp_itemids di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id
),
categorized AS (
  SELECT
    subject_id,
    CASE
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp BETWEEN 140 AND 159 THEN '140-159'
      WHEN avg_sbp >= 160 THEN '≥160'
    END AS sbp_category
  FROM first_24h_sbp
)
SELECT
  sbp_category,
  COUNT(DISTINCT subject_id) AS unique_patients
FROM categorized
GROUP BY sbp_category
ORDER BY sbp_category;