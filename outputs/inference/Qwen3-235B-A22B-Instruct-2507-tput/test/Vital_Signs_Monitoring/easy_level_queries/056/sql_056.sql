WITH temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%temperature%'
),
patient_icu_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 46 AND 56
),
temperature_measurements AS (
  SELECT 
    pia.stay_id,
    ce.charttime,
    ce.valuenum AS temp_raw,
    di.label,
    LOWER(ce.valueuom) AS uom,
    CASE
      WHEN LOWER(ce.valueuom) LIKE '%f%' THEN ce.valuenum
      WHEN LOWER(ce.valueuom) LIKE '%c%' THEN (ce.valuenum * 9/5) + 32
      ELSE NULL
    END AS temp_f
  FROM patient_icu_age pia
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON pia.stay_id = ce.stay_id
  INNER JOIN temperature_items ti
    ON ce.itemid = ti.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= pia.intime
    AND ce.charttime <= DATETIME_ADD(pia.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
)
SELECT
  APPROX_QUANTILES(temp_f, 100)[OFFSET(50)] AS median_temperature_f
FROM temperature_measurements
WHERE temp_f IS NOT NULL;