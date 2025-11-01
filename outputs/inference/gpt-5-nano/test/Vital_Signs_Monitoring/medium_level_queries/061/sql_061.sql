WITH eligible AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    AVG(cte.valuenum) AS map_mean
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS cte
    ON cte.subject_id = icu.subject_id
   AND cte.hadm_id = icu.hadm_id
   AND cte.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = cte.itemid
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    AND cte.charttime >= icu.intime
    AND cte.charttime <= icu.outtime
    AND cte.valuenum IS NOT NULL
    AND UPPER(p.gender) = 'MALE'
    AND p.anchor_age BETWEEN 38 AND 48
  GROUP BY icu.subject_id, icu.stay_id
)

SELECT
  SAFE_DIVIDE(COUNTIF(map_mean <= 60), COUNT(*)) AS pct_le_60
FROM eligible;