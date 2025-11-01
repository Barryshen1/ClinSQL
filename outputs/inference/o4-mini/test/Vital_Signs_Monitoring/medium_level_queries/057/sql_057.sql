WITH temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
),

patient_cohort AS (
  SELECT p.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),

stay_avg_temps AS (
  SELECT
    pc.stay_id,
    AVG(ce.valuenum) AS avg_temp_c
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = pc.stay_id
  JOIN temp_items ti
    ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.valueuom = 'C'
    AND ce.charttime BETWEEN
        (SELECT intime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = pc.stay_id)
      AND
        (SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = pc.stay_id)
  GROUP BY pc.stay_id
  HAVING AVG(ce.valuenum) IS NOT NULL
),

percentile_calc AS (
  SELECT
    COUNTIF(avg_temp_c <= 36.0) AS count_le_36,
    COUNT(*) AS total_stays
  FROM stay_avg_temps
)

SELECT
  count_le_36,
  total_stays,
  SAFE_DIVIDE(count_le_36, total_stays) AS percentile_rank_36
FROM percentile_calc;