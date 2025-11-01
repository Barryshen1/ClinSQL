WITH female_patients_82_92 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 82 AND 92
),

hospital_stays AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients_82_92 p ON a.subject_id = p.subject_id
),

map_values AS (
  SELECT
    ce.hadm_id,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE
    di.label = 'Mean Arterial Pressure'
    AND ce.hadm_id IN (SELECT hadm_id FROM hospital_stays)
),

max_map_per_stay AS (
  SELECT
    hadm_id,
    MAX(map_value) AS max_map
  FROM
    map_values
  GROUP BY
    hadm_id
)

SELECT
  PERCENTILE_CONT(max_map, 0.5) OVER() AS median_max_map
FROM
  max_map_per_stay
LIMIT 1;