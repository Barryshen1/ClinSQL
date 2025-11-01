WITH male_icu_adms AS (
  SELECT DISTINCT p.subject_id, i.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
),
first_sodium_time AS (
  SELECT 
    l.hadm_id, 
    MIN(l.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN male_icu_adms m ON l.hadm_id = m.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d ON l.itemid = d.itemid
  WHERE l.charttime >= m.admittime
    AND d.label = 'Sodium'
    AND d.category = 'Chemistry'
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),
first_sodium_values AS (
  SELECT 
    l.hadm_id,
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
  INNER JOIN first_sodium_time f ON l.hadm_id = f.hadm_id AND l.charttime = f.first_charttime
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems d ON l.itemid = d.itemid
  INNER JOIN male_icu_adms m ON l.hadm_id = m.hadm_id
  WHERE d.label = 'Sodium'
    AND d.category = 'Chemistry'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= m.admittime
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
FROM first_sodium_values;