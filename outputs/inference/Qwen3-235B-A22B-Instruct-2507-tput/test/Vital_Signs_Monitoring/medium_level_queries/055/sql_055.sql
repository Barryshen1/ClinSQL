WITH patient_icu AS (
  SELECT
    i.stay_id,
    i.intime,
    i.outtime,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 87 AND 97
),

spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),

stay_spo2_averages AS (
  SELECT
    p.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM patient_icu p
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON p.stay_id = ce.stay_id
  JOIN spo2_items s
    ON ce.itemid = s.itemid
  WHERE ce.charttime >= p.intime
    AND ce.charttime < DATETIME_ADD(p.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
  GROUP BY p.stay_id
)

SELECT
  SAFE_DIVIDE(COUNTIF(avg_spo2 <= 88), COUNT(*)) * 100 AS percentile
FROM stay_spo2_averages;