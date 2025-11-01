WITH female_patients AS (
  SELECT subject_id, gender, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
),
icu_stays_with_age AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN female_patients p ON i.subject_id = p.subject_id
  WHERE (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 38 AND 48
),
spo2_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE REGEXP_CONTAINS(LOWER(label), r'spo2')
),
spo2_per_stay AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN spo2_item s ON ce.itemid = s.itemid
  INNER JOIN icu_stays_with_age i ON ce.stay_id = i.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.outtime
    AND ce.valuenum >= 0
    AND ce.valuenum <= 100
  GROUP BY ce.stay_id
),
summary_stats AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNTIF(mean_spo2 <= 92) AS stays_with_mean_spo2_lte_92
  FROM spo2_per_stay
)
SELECT
  CASE
    WHEN total_stays = 0 THEN NULL
    ELSE (stays_with_mean_spo2_lte_92 * 100.0 / total_stays)
  END AS percentile_rank
FROM summary_stats;