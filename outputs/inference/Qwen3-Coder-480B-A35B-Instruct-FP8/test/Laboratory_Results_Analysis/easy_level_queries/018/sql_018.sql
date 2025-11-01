SELECT
  APPROX_QUANTILES(first_pH, 2)[OFFSET(1)] AS median_pH_on_ICU_admission
FROM (
  SELECT
    ce.stay_id,
    MIN(ce.valuenum) AS first_pH
  FROM
    physionet-data.mimiciv_3_1_icu.icustays AS icu
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.chartevents AS ce
    ON icu.stay_id = ce.stay_id
  INNER JOIN
    physionet-data.mimiciv_3_1_icu.d_items AS di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'F'
    AND LOWER(di.label) LIKE '%ph%'
    AND LOWER(di.category) LIKE '%blood gas%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 6 HOUR)
  GROUP BY
    ce.stay_id
);