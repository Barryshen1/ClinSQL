WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 38 AND 48
),
PatientICUStays AS (
  SELECT
    p.subject_id,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON p.subject_id = ic.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 38 AND 48
),
MAPValues AS (
  SELECT
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON ce.stay_id = ic.stay_id
  WHERE
    di.label = 'Mean Arterial Pressure'
    AND ce.valuenum IS NOT NULL
),
AverageMAP AS (
  SELECT
    ic.stay_id,
    AVG(map_value) AS avg_map
  FROM
    MAPValues AS mv
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON mv.stay_id = ic.stay_id
  GROUP BY
    ic.stay_id
),
PercentileRank AS (
  SELECT
    avg_map,
    COUNT(*) AS count_le_60
  FROM
    AverageMAP
  WHERE
    avg_map <= 60
  GROUP BY
    avg_map
)
SELECT
  avg_map,
  count_le_60,
  (
    count_le_60 / (
      SELECT
        COUNT(*)
      FROM
        AverageMAP
    )
  ) * 100 AS percentile_rank
FROM
  PercentileRank
ORDER BY
  avg_map;