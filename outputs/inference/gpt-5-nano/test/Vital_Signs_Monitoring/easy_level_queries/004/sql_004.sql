WITH per_stay AS (
  SELECT
    icu.stay_id,
    AVG(
      CASE
        -- Convert Fahrenheit to Celsius if needed
        WHEN LOWER(c.valueuom) LIKE '%f%' THEN (c.valuenum - 32) * 5.0/9.0
        ELSE c.valuenum
      END
    ) AS mean_temp_c
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON c.subject_id = icu.subject_id
   AND c.hadm_id    = icu.hadm_id
   AND c.stay_id    = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE REGEXP_CONTAINS(LOWER(di.label), r'(temperature|temp)')
    AND c.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
  GROUP BY icu.stay_id
)
SELECT
  APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(75)] AS p75_mean_temp_c
FROM per_stay;