SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_ph
FROM (
  SELECT ce.valuenum
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays icu
    ON p.subject_id = icu.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON icu.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND di.label IN ('pH', 'Arterial pH', 'ABG pH')
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 2 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 6.8
    AND ce.valuenum < 7.8
) AS filtered_ph_values;