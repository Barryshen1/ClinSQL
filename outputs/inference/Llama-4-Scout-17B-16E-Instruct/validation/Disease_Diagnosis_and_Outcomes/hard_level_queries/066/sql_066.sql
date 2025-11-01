WITH 
selected_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    dc.drg_severity AS risk_score  
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
      ON a.subject_id = dc.subject_id AND a.hadm_id = dc.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN (
        SELECT icd_code 
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE long_title LIKE '%Pulmonary Embolism%'
      )
    )
),
mortality AS (
  SELECT 
    subject_id,
    hadm_id,
    deathtime,
    dischtime,
    CASE 
      WHEN deathtime IS NOT NULL AND TIMESTAMP_ADD(dischtime, INTERVAL 90 DAY) < TIMESTAMP_CURRENT_TIMESTAMP() THEN 1 
      ELSE 0 
    END AS died_within_90_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
aki_ards AS (
  SELECT 
    ic.stay_id,
    COUNT(DISTINCT CASE WHEN di.label LIKE '%Acute kidney failure%' THEN di.label END) AS aki_count,
    COUNT(DISTINCT CASE WHEN di.label LIKE '%Acute respiratory distress syndrome%' THEN di.label END) AS ards_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON ic.stay_id = ce.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON ce.itemid = di.itemid
  GROUP BY 
    ic.stay_id
),
risk_score_percentile AS (
  SELECT 
    APPROX_QUANTILES(risk_score, 1000)[751] AS percentile_75
  FROM (
    SELECT drg_severity AS risk_score 
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
  ) AS risk_scores
),
high_risk_patients AS (
  SELECT 
    sp.*,
    rsp.percentile_75
  FROM 
    selected_patients sp
  CROSS JOIN 
    risk_score_percentile rsp
  WHERE 
    sp.risk_score > rsp.percentile_75
)

SELECT 
  AVG(hrp.risk_score) AS mean_risk_score,
  AVG(m.died_within_90_days) AS ninety_day_mortality_rate,
  AVG(CASE WHEN aki_count > 0 THEN 1 ELSE 0 END) AS aki_rate,
  AVG(CASE WHEN ards_count > 0 THEN 1 ELSE 0 END) AS ards_rate,
  AVG(DATEDIFF(a.dischtime, a.admittime)) AS los_days
FROM 
  high_risk_patients hrp
JOIN 
  mortality m 
    ON hrp.subject_id = m.subject_id AND hrp.hadm_id = m.hadm_id
LEFT JOIN 
  aki_ards 
    ON hrp.hadm_id = ANY(SELECT hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE stay_id = aki_ards.stay_id)
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON hrp.subject_id = a.subject_id AND hrp.hadm_id = a.hadm_id;