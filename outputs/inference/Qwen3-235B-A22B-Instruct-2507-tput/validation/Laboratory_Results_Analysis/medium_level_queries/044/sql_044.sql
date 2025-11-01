WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    -- Compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 54 AND 64
),
troponin_t_events AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),
first_troponin_per_admission AS (
  SELECT
    pa.hadm_id,
    FIRST_VALUE(te.valuenum) OVER (
      PARTITION BY te.hadm_id
      ORDER BY te.charttime
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_troponin_value
  FROM patient_admissions pa
  INNER JOIN troponin_t_events te
    ON pa.hadm_id = te.hadm_id
),
filtered_first_troponin AS (
  SELECT
    first_troponin_value
  FROM first_troponin_per_admission
  WHERE first_troponin_value > 0.01
)
SELECT
  COUNT(*) AS n,
  AVG(first_troponin_value) AS mean,
  STDDEV(first_troponin_value) AS std,
  MIN(first_troponin_value) AS min,
  MAX(first_troponin_value) AS max,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(75)] AS p75
FROM filtered_first_troponin;