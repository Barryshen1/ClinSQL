WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
),
first_icu_stay AS (
  SELECT hadm_id, stay_id, intime
  FROM (
    SELECT hadm_id, stay_id, intime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM eligible_patients)
  )
  WHERE rn = 1
),
rr_events AS (
  SELECT 
    ep.hadm_id,
    fis.stay_id,
    fis.intime,
    ce.charttime,
    ce.valuenum AS rr
  FROM eligible_patients ep
  INNER JOIN first_icu_stay fis
    ON ep.hadm_id = fis.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ep.subject_id = ce.subject_id
    AND ep.hadm_id = ce.hadm_id
    AND fis.stay_id = ce.stay_id
  WHERE ce.itemid IN (618, 619, 220210)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fis.intime
),
first_rr_per_stay AS (
  SELECT 
    hadm_id,
    MIN(rr) AS first_rr
  FROM (
    SELECT 
      hadm_id,
      rr,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
    FROM rr_events
  )
  WHERE rn = 1
  GROUP BY hadm_id
)
SELECT STDDEV(first_rr) AS sd_first_respiratory_rate
FROM first_rr_per_stay
WHERE first_rr IS NOT NULL;