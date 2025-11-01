SELECT
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_gcs_total
FROM
  physionet-data.mimiciv_3_1_hosp.patients p
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
  ON p.subject_id = icu.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 88 AND 98
  AND LOWER(di.label) LIKE '%high flow nasal cannula%'
  AND ce.charttime >= icu.intime + INTERVAL 1 DAY
  AND EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_icu.d_items gcs
    JOIN physionet-data.mimiciv_3_1_icu.chartevents gcs_ce
      ON gcs.itemid = gcs_ce.itemid
    WHERE
      LOWER(gcs.label) = 'gcs total'
      AND gcs_ce.stay_id = icu.stay_id
      AND gcs_ce.charttime >= icu.intime + INTERVAL 1 DAY
      AND gcs_ce.valuenum IS NOT NULL
  )
  AND LOWER(di.label) LIKE '%high flow nasal cannula%';