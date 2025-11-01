WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(label) LIKE '%blood pressure%'
),

female_45_55_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
),

sbp_first24h AS (
  SELECT
    f.subject_id,
    f.stay_id,
    AVG(c.valuenum) AS avg_sbp
  FROM female_45_55_icu f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id
    AND f.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM sbp_itemids)
    AND c.valuenum IS NOT NULL
    AND c.charttime >= f.intime
    AND c.charttime < TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY f.subject_id, f.stay_id
),

sbp_category AS (
  SELECT
    subject_id,
    stay_id,
    avg_sbp,
    CASE
      WHEN avg_sbp < 140 THEN '<140'
      WHEN avg_sbp >= 140 AND avg_sbp < 160 THEN '140–159'
      WHEN avg_sbp >= 160 THEN '≥160'
      ELSE NULL
    END AS sbp_group
  FROM sbp_first24h
  WHERE avg_sbp IS NOT NULL
)

SELECT
  sbp_group,
  COUNT(DISTINCT subject_id) AS unique_patient_count
FROM sbp_category
WHERE sbp_group IS NOT NULL
GROUP BY sbp_group
ORDER BY
  CASE sbp_group
    WHEN '<140' THEN 1
    WHEN '140–159' THEN 2
    WHEN '≥160' THEN 3
    ELSE 4
  END;