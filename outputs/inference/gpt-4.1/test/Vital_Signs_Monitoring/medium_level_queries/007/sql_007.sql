WITH spo2_items AS (
  -- Find itemids for SpO2 in d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%'
),
female_80_90_stays AS (
  -- Get ICU stays for female patients aged 80-90
  SELECT icu.stay_id, icu.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
),
stay_avg_spo2 AS (
  -- Compute average SpO2 per ICU stay
  SELECT
    s.stay_id,
    AVG(c.valuenum) AS avg_spo2
  FROM female_80_90_stays s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE c.itemid IN (SELECT itemid FROM spo2_items)
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
)
SELECT
  COUNTIF(avg_spo2 <= 88) / COUNT(*) * 100 AS percentile_88_spo2
FROM stay_avg_spo2
WHERE avg_spo2 IS NOT NULL;