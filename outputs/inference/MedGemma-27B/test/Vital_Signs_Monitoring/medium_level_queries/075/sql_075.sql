WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 56 AND 66
),
ICUStays AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    icustays.intime,
    icustays.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  INNER JOIN
    PatientAge
    ON icustays.subject_id = PatientAge.subject_id
),
MAPValues AS (
  SELECT
    icustays.subject_id,
    icustays.stay_id,
    chartevents.charttime,
    chartevents.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents`
  INNER JOIN
    ICUStays
    ON chartevents.subject_id = icustays.subject_id AND chartevents.stay_id = icustays.stay_id
  WHERE
    chartevents.itemid = 455
),
MAPStats AS (
  SELECT
    subject_id,
    stay_id,
    AVG(map_value) AS avg_map
  FROM
    MAPValues
  GROUP BY
    subject_id,
    stay_id
),
MAPCategories AS (
  SELECT
    subject_id,
    stay_id,
    CASE
      WHEN avg_map < 65 THEN '<65'
      WHEN avg_map BETWEEN 65 AND 74 THEN '65-74'
      WHEN avg_map BETWEEN 75 AND 84 THEN '75-84'
      ELSE '>=85'
    END AS map_category
  FROM
    MAPStats
)
SELECT
  map_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN map_category = '>=85' THEN subject_id ELSE NULL END) AS stroke_count
FROM
  MAPCategories
GROUP BY
  map_category
ORDER BY
  map_category;