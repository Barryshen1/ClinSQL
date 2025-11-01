WITH first_spo2_per_icu AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    ce.charttime AS spo2_time,
    ce.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE
    p.gender = 'M'
    -- age at ICU admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 37 AND 47
    -- identify SpO2-related items
    AND (LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%')
    -- ensure charttime corresponds to the ICU stay
    AND ce.charttime >= i.intime
    AND ce.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY i.subject_id, i.hadm_id, i.stay_id
    ORDER BY ce.charttime
  ) = 1
)

SELECT
  q[OFFSET(25)] AS spo2_q1,
  q[OFFSET(75)] AS spo2_q3,
  (q[OFFSET(75)] - q[OFFSET(25)]) AS spo2_iqr
FROM (
  SELECT APPROX_QUANTILES(spo2_value, 100) AS q
  FROM first_spo2_per_icu
  WHERE spo2_value IS NOT NULL
) t;