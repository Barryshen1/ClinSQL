WITH sepsis_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  WHERE p.anchor_age BETWEEN 78 AND 88
    AND p.gender = 'M'
    AND d.icd_version IN (9, 10)
    AND d.icd_code IN (
      '995.91', '995.92',  -- ICD-9 sepsis
      'A41.9', 'R65.20', 'R65.21', 'R65.22'  -- ICD-10 sepsis, severe sepsis, septic shock
    )
),
icu_hr AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    sp.hospital_expire_flag,
    i.intime,
    i.outtime,
    ce.valuenum AS heart_rate,
    i.los AS icu_los_days
  FROM sepsis_patients sp
  JOIN physionet-data.mimiciv_3_1_icu.icustays i ON sp.subject_id = i.subject_id
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce ON i.stay_id = ce.stay_id
  WHERE ce.itemid = 220045  -- Heart rate
    AND ce.charttime >= i.intime
    AND ce.charttime <= DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
hr_percentiles AS (
  SELECT 
    heart_rate,
    PERCENT_RANK() OVER (ORDER BY heart_rate) AS percentile_rank,
    NTILE(4) OVER (ORDER BY heart_rate) AS hr_quartile,
    icu_los_days,
    hospital_expire_flag
  FROM icu_hr
)
SELECT
  (SELECT MAX(percentile_rank) FROM hr_percentiles WHERE heart_rate = 85) AS percentile_rank_of_85,
  AVG(CASE WHEN hr_quartile = 4 THEN icu_los_days END) AS mean_icu_los_q4,
  AVG(CASE WHEN hr_quartile = 4 THEN CAST(hospital_expire_flag AS FLOAT64) END) AS hospital_mortality_rate_q4
FROM hr_percentiles;