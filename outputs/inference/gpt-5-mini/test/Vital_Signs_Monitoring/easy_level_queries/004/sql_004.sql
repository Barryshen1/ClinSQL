WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 37 AND 47
),

temp_measurements AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.valuenum,
    ce.valueuom,
    di.unitname,
    LOWER(COALESCE(ce.valueuom, di.unitname, '')) AS unit_lower,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(ce.valueuom, di.unitname, '')),
                           r'(^|[^a-z])(f|°f|fahrenheit)($|[^a-z])')
        THEN (ce.valuenum - 32.0) * 5.0 / 9.0
      WHEN REGEXP_CONTAINS(LOWER(COALESCE(ce.valueuom, di.unitname, '')),
                           r'(°c|celsius|centigrade|(^|[^a-z])c($|[^a-z]))')
        THEN ce.valuenum
      ELSE NULL
    END AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.stay_id = ce.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE icu.subject_id IN (SELECT subject_id FROM female_patients)
    AND ce.valuenum IS NOT NULL
    -- restrict to items labeled as temperature to avoid non-temperature numeric items
    AND di.label IS NOT NULL
    AND LOWER(di.label) LIKE '%temp%'
),

stay_mean_temps AS (
  SELECT
    stay_id,
    subject_id,
    AVG(temp_c) AS mean_temp_c,
    COUNT(*) AS n_temp_measurements
  FROM temp_measurements
  WHERE temp_c BETWEEN 30.0 AND 45.0    -- plausibility filter in Celsius
  GROUP BY stay_id, subject_id
)

SELECT
  APPROX_QUANTILES(mean_temp_c, 100)[OFFSET(75)] AS p75_mean_temp_c,
  COUNT(*) AS n_stays_included
FROM stay_mean_temps;