WITH spo2_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),
icu_stays_with_age_gender AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 38 AND 48
),
spo2_per_stay AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spo2_itemids s ON ce.itemid = s.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY ce.stay_id
),
filtered_stays AS (
  SELECT 
    iss.stay_id,
    iss.mean_spo2
  FROM spo2_per_stay iss
  JOIN icu_stays_with_age_gender icu
    ON iss.stay_id = icu.stay_id
)
SELECT
  AVG(CASE WHEN mean_spo2 <= 92 THEN 1 ELSE 0 END) * 100 AS percentile_rank
FROM filtered_stays;