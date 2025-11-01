WITH per_stay_map AS (
  SELECT
    st.stay_id,
    st.subject_id,
    st.hadm_id,
    st.intime,
    AVG(ce.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS st
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON st.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON st.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 39 AND 49
    AND di.label LIKE '%Mean arterial pressure%'
    AND ce.charttime >= st.intime
    AND ce.charttime <= TIMESTAMP_ADD(st.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY st.stay_id, st.subject_id, st.hadm_id, st.intime
)

SELECT
  100.0 * SUM(CASE WHEN mean_map <= 75 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_75
FROM per_stay_map;