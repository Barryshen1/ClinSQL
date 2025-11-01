WITH patient_age AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age BETWEEN 45 AND 55
),

vital_signs_48h AS (
  SELECT
    ce.stay_id,
    di.label,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON ce.stay_id = i.stay_id
  WHERE di.label IN ('Mean Blood Pressure', 'Heart Rate')
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

aggregated_vitals AS (
  SELECT
    i.subject_id,
    i.stay_id,
    MIN(IF(vs.label = 'Mean Blood Pressure', vs.valuenum, NULL)) AS min_map,
    MAX(IF(vs.label = 'Heart Rate', vs.valuenum, NULL)) AS max_hr
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  LEFT JOIN vital_signs_48h vs
    ON i.stay_id = vs.stay_id
  INNER JOIN patient_age pa
    ON i.subject_id = pa.subject_id
  GROUP BY i.subject_id, i.stay_id
),

instability_scores AS (
  SELECT
    subject_id,
    stay_id,
    min_map,
    max_hr,
    CASE WHEN min_map < 65 THEN 1 ELSE 0 END AS hypotension_flag,
    CASE WHEN max_hr > 100 THEN 1 ELSE 0 END AS tachycardia_flag,
    (CASE WHEN min_map < 65 THEN 1 ELSE 0 END) + (CASE WHEN max_hr > 100 THEN 1 ELSE 0 END) AS instability_score
  FROM aggregated_vitals
)

SELECT
  APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability_score
FROM instability_scores;