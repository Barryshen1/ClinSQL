WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),

transplant_flag AS (
  SELECT 
    p.subject_id,
    CASE WHEN d.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_transplant
  FROM patients_filtered p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
    AND d.icd_code LIKE 'Z94%'
),

icustays_filtered AS (
  SELECT 
    i.stay_id, 
    i.hadm_id, 
    i.intime, 
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patients_filtered p ON i.subject_id = p.subject_id
),

composite_score AS (
  SELECT 
    i.stay_id,
    COALESCE(SUM(
      CASE WHEN c.itemid = 223761 AND c.valuenum > 38.5 THEN 1 ELSE 0 END +
      CASE WHEN c.itemid = 220277 AND c.valuenum < 90 THEN 1 ELSE 0 END +
      CASE WHEN c.itemid = 220210 AND c.valuenum > 20 THEN 1 ELSE 0 END
    ), 0) AS composite_score
  FROM icustays_filtered i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
    AND c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.stay_id
),

admissions_mortality AS (
  SELECT hadm_id, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT
  tf.is_transplant,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cs.composite_score) AS median_composite,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY cs.composite_score) AS p25_composite,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY cs.composite_score) AS p75_composite,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY i.los) AS median_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY i.los) AS p25_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY i.los) AS p75_los,
  AVG(CAST(am.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM icustays_filtered i
LEFT JOIN transplant_flag tf ON i.subject_id = tf.subject_id
LEFT JOIN composite_score cs ON i.stay_id = cs.stay_id
LEFT JOIN admissions_mortality am ON i.hadm_id = am.hadm_id
GROUP BY tf.is_transplant;