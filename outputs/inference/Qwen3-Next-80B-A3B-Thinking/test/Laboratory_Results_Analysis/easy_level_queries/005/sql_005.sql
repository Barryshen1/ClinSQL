WITH first_sodium AS (
  SELECT
    i.stay_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON l.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND l.itemid = 50983
    AND l.charttime BETWEEN i.intime AND i.outtime
    AND l.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(valuenum, 0.25) OVER () AS q25,
  PERCENTILE_CONT(valuenum, 0.75) OVER () AS q75,
  PERCENTILE_CONT(valuenum, 0.75) OVER () - PERCENTILE_CONT(valuenum, 0.25) OVER () AS iqr
FROM first_sodium
WHERE rn = 1
LIMIT 1;