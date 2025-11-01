WITH first_map_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY icu.subject_id, icu.hadm_id, icu.stay_id
      ORDER BY ce.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    -- MAP value within the ICU stay window
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
    -- Filters for male patients aged 55-65
    AND LOWER(p.gender) IN ('m','male')
    AND p.anchor_age BETWEEN 55 AND 65
)
SELECT STDDEV_SAMP(valuenum) AS sd_first_map
FROM first_map_per_stay
WHERE rn = 1;