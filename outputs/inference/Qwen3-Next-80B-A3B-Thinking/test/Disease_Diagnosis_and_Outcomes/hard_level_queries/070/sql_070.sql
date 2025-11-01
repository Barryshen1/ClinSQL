WITH dvt_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I82.4%')
      OR (d.icd_version = 9 AND d.icd_code IN ('451.1', '451.2', '451.8', '451.9'))
    )
),

charlson_conditions AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')) THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code LIKE '440%' OR d.icd_code = '443.9')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'I70%' OR d.icd_code LIKE 'I73%')) THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I69') THEN 1 ELSE 0 END) AS cerebrovascular,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '290%') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'F01' AND 'F03') THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '490' AND '496') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'J40' AND 'J47') THEN 1 ELSE 0 END) AS chronic_pulmonary,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '710%') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'M05' AND 'M06') THEN 1 ELSE 0 END) AS rheumatic,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '531' AND '534') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K25' AND 'K28') THEN 1 ELSE 0 END) AS peptic_ulcer,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '570' AND '571') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'K70' AND 'K77') THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code = '250.0') OR (d.icd_version = 10 AND (d.icd_code = 'E10.0' OR d.icd_code = 'E11.0' OR d.icd_code = 'E13.0')) THEN 1 ELSE 0 END) AS diabetes_uncomplicated,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.%' AND d.icd_code != '250.0') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.%' OR d.icd_code LIKE 'E11.%' OR d.icd_code LIKE 'E13.%') AND d.icd_code NOT IN ('E10.0', 'E11.0', 'E13.0'))) THEN 1 ELSE 0 END) AS diabetes_complicated,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '342%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'G81%' OR d.icd_code LIKE 'G82%')) THEN 1 ELSE 0 END) AS paralysis,
    MAX(CASE WHEN (d.icd_version = 9 AND (d.icd_code = '585' OR d.icd_code = '586' OR d.icd_code = '588.0')) OR (d.icd_version = 10 AND (d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'N19%' OR d.icd_code = 'N25.0')) THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '140' AND '208') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C00' AND 'C97') THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code IN ('571.5', '571.6', '572.3', '572.4', '572.8', '572.9')) OR (d.icd_version = 10 AND (d.icd_code IN ('K70.3', 'K71.5', 'K72.1', 'K72.9', 'K76.0', 'K76.5', 'K76.6'))) THEN 1 ELSE 0 END) AS severe_liver,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code BETWEEN '196' AND '199') OR (d.icd_version = 10 AND d.icd_code BETWEEN 'C77' AND 'C80') THEN 1 ELSE 0 END) AS metastatic,
    MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code = '042') OR (d.icd_version = 10 AND d.icd_code = 'B20') THEN 1 ELSE 0 END) AS aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY d.subject_id, d.hadm_id
),

charlson_scores AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    (mi * 1 + chf * 1 + pvd * 1 + cerebrovascular * 1 + dementia * 1 + chronic_pulmonary * 1 + rheumatic * 1 + peptic_ulcer * 1 + mild_liver * 1 + diabetes_uncomplicated * 1 + diabetes_complicated * 2 + paralysis * 2 + renal * 2 + malignancy * 2 + severe_liver * 3 + metastatic * 6 + aids * 6) AS charlson_score
  FROM charlson_conditions c
  JOIN dvt_patients d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
),

p75 AS (
  SELECT PERCENTILE_CONT(charlson_score, 0.75) WITHIN GROUP (ORDER BY charlson_score) AS p75_value
  FROM charlson_scores
),

filtered_cohort AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.charlson_score,
    d.admittime,
    d.dischtime,
    d.deathtime
  FROM charlson_scores c
  JOIN dvt_patients d
    ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  CROSS JOIN p75
  WHERE c.charlson_score > p75.p75_value
),

major_complications AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    MAX(CASE WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I26%') OR (d.icd_version = 9 AND d.icd_code IN ('415.0', '415.1')) THEN 1 ELSE 0 END) AS pe
  FROM filtered_cohort f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  GROUP BY f.subject_id, f.hadm_id
),

survival_times AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    TIMESTAMP_DIFF(f.deathtime, f.admittime, DAY) AS survival_days
  FROM filtered_cohort f
  WHERE f.deathtime IS NOT NULL
),

quartiles AS (
  SELECT
    NTILE(4) OVER (ORDER BY charlson_score) AS quartile,
    COUNT(*) AS count
  FROM filtered_cohort
  GROUP BY quartile
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(CASE WHEN deathtime IS NOT NULL AND deathtime <= admittime + INTERVAL '30' DAY THEN 1 ELSE 0 END) AS thirty_day_mortality,
  AVG(CASE WHEN pe = 1 THEN 1 ELSE 0 END) AS major_complication_rate,
  PERCENTILE_CONT(survival_days, 0.5) WITHIN GROUP (ORDER BY survival_days) AS median_survival_decedents,
  ARRAY_AGG(STRUCT(quartile, count)) AS composite_risk_score_quartiles
FROM filtered_cohort f
LEFT JOIN major_complications mc
  ON f.subject_id = mc.subject_id AND f.hadm_id = mc.hadm_id
LEFT JOIN survival_times st
  ON f.subject_id = st.subject_id AND f.hadm_id = st.hadm_id
CROSS JOIN quartiles;