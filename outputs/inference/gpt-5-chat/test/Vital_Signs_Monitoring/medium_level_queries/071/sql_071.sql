WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%spo2%'
),
spo2_per_stay AS (
  SELECT
    ce.stay_id,
    p.gender,
    p.anchor_age,
    AVG(ce.valuenum) AS mean_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN spo2_items si
    ON ce.itemid = si.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id AND icu.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0 AND ce.valuenum <= 100
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
  GROUP BY ce.stay_id, p.gender, p.anchor_age
),
stats AS (
  SELECT
    COUNTIF(mean_spo2 <= 92) AS n_le_92,
    COUNT(*) AS total_stays
  FROM spo2_per_stay
)
SELECT
  n_le_92,
  total_stays,
  SAFE_DIVIDE(n_le_92, total_stays) AS proportion_le_92
FROM stats;