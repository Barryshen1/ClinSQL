SELECT DISTINCT PERCENTILE_CONT(temperature_fahrenheit, 0.5) OVER() AS median_temperature_fahrenheit
FROM (
  SELECT 
    CASE 
      WHEN d.label = 'Temperature F' THEN c.valuenum
      WHEN d.label IN ('Temperature', 'Temperature C') THEN (c.valuenum * 9/5) + 32
    END AS temperature_fahrenheit
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND d.label IN ('Temperature', 'Temperature C', 'Temperature F')
    AND c.charttime >= i.intime
    AND c.charttime <= i.intime + INTERVAL '24 hour'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 50
) AS temp_fahrenheit_values;