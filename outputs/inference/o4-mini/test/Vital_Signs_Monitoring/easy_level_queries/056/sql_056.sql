SELECT
  APPROX_QUANTILES(temp_f, 2)[OFFSET(1)] AS median_temperature_f
FROM (
  SELECT
    CASE
      WHEN LOWER(c.valueuom) IN ('c', 'cel', '°c', 'celsius')
        THEN (c.valuenum * 9.0/5.0) + 32.0
      WHEN LOWER(c.valueuom) IN ('f', '°f', 'fahrenheit')
        THEN c.valuenum
      ELSE NULL
    END AS temp_f
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id
    AND i.hadm_id    = c.hadm_id
    AND i.stay_id    = c.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND c.charttime BETWEEN i.intime
                       AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
    AND LOWER(d.label) LIKE '%temp%'
    AND c.valuenum IS NOT NULL
)
WHERE temp_f IS NOT NULL;