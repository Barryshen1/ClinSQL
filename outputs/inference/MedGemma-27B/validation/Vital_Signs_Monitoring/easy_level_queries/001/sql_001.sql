WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    subject_id = 57 -- Specific patient ID
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    PatientInfo AS p
    ON s.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
), FirstMAP AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    ICUStays AS icu
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.subject_id = ce.subject_id
    AND icu.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'Mean Arterial Pressure'
    AND ce.charttime = (
      SELECT
        MIN(charttime)
      FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_inner
      WHERE
        ce_inner.subject_id = ce.subject_id
        AND ce_inner.stay_id = ce.stay_id
        AND ce_inner.itemid = ce.itemid
    )
)
SELECT
  PERCENTILE_CONT(0.25, map_value) AS iqr_25,
  PERCENTILE_CONT(0.75, map_value) AS iqr_75
FROM
  FirstMAP;