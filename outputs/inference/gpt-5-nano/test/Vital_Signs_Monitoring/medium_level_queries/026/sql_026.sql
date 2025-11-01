WITH per_stay_rr AS (
  SELECT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    AVG(ce.valuenum) AS rr_avg
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < i.intime + INTERVAL 48 HOUR
    -- Case-insensitive label matching for respiratory rate
    AND LOWER(di.label) LIKE '%respiratory rate%'
  GROUP BY i.stay_id, i.subject_id, i.hadm_id
)

SELECT
  100.0 * SUM(CASE WHEN ps.rr_avg <= 12 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_12
FROM per_stay_rr AS ps
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = ps.subject_id
WHERE
  UPPER(p.gender) = 'MALE'
  AND p.anchor_age BETWEEN 68 AND 78
  AND ps.rr_avg IS NOT NULL;