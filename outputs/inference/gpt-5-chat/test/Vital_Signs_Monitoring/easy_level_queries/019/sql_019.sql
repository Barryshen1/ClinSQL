WITH map_events AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    -- identify MAP measurements by item label
    di.label LIKE '%Mean Arterial Pressure%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
)
SELECT
  ie.subject_id,
  ie.hadm_id,
  ie.stay_id,
  AVG(me.valuenum) AS avg_map
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` ie
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON ie.subject_id = p.subject_id
JOIN
  map_events me
  ON ie.stay_id = me.stay_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 73 AND 83
  AND (
    UPPER(ie.first_careunit) LIKE '%STEPDOWN%'
    OR UPPER(ie.first_careunit) LIKE '%IMC%'
    OR UPPER(ie.last_careunit) LIKE '%STEPDOWN%'
    OR UPPER(ie.last_careunit) LIKE '%IMC%'
  )
GROUP BY
  ie.subject_id,
  ie.hadm_id,
  ie.stay_id
ORDER BY
  ie.subject_id,
  ie.stay_id;