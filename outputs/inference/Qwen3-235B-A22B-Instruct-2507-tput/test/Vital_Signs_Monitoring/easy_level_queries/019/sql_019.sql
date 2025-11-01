WITH map_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND LOWER(icu.first_careunit) LIKE '%step%'
    OR LOWER(icu.first_careunit) LIKE '%intermediate%'
    AND LOWER(di.label) LIKE '%arterial pressure%mean%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
  GROUP BY
    ce.stay_id
)
SELECT
  AVG(mean_map) AS average_of_mean_arterial_pressure_per_stay
FROM
  map_per_stay;