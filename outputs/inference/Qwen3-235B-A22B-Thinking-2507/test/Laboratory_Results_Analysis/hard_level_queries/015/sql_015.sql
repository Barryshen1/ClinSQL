WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 49 AND 59
),
stroke_admissions AS (
  SELECT DISTINCT
    ep.hadm_id,
    ep.admittime
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON ep.hadm_id = d.hadm_id
  WHERE 
    d.icd_code LIKE 'I63%'
    AND d.icd_version = 10
),
lab_scores AS (
  SELECT
    sa.hadm_id,
    COUNT(CASE 
            WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper 
            THEN 1 
          END) AS instability_score
  FROM stroke_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l
    ON sa.hadm_id = l.hadm_id
    AND l.charttime >= sa.admittime
    AND l.charttime < DATETIME_ADD(sa.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY sa.hadm_id
)
SELECT
  APPROX_QUANTILES(instability_score, 1000)[OFFSET(750)] AS p75_instability_score
FROM lab_scores;