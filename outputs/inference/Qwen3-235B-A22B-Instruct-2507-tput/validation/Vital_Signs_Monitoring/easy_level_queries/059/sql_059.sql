WITH spo2_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) = 'spo2'
),
first_spo2_per_admission AS (
  SELECT
    ce.hadm_id,
    MIN(ce.charttime) AS first_spo2_time
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN spo2_item si ON ce.itemid = si.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON ce.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 77 AND 87
    AND p.gender = 'M'
    AND ce.charttime >= a.admittime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100  -- SpO2 should be 0-100%
  GROUP BY ce.hadm_id
),
first_spo2_values AS (
  SELECT
    ce.valuenum AS first_spo2
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN spo2_item si ON ce.itemid = si.itemid
  INNER JOIN first_spo2_per_admission f ON ce.hadm_id = f.hadm_id AND ce.charttime = f.first_spo2_time
)
SELECT
  STDDEV(first_spo2) AS spo2_stddev
FROM first_spo2_values;