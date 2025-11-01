WITH rr_itemids AS (
  /* Identify itemids that look like respiratory rate measurements */
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respir%' 
    AND (
      LOWER(label) LIKE '%rate%' 
      OR LOWER(label) LIKE '%respiration%' 
      OR LOWER(label) LIKE '%respirations%' 
      OR LOWER(label) LIKE '%rr%'
    )
),

first_rr_per_admission AS (
  /*
    For each hospital admission that has an ICU stay with respiratory-rate measurements,
    pick the first respiratory-rate valuenum on or after admittime and within 24 hours.
  */
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm,
    -- first numeric respiratory rate within the 24-hour window after admittime
    ARRAY_AGG(c.valuenum ORDER BY c.charttime ASC LIMIT 1)[OFFSET(0)] AS first_rr
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = i.stay_id
  JOIN rr_itemids r
    ON c.itemid = r.itemid
  WHERE c.valuenum IS NOT NULL
    AND c.charttime >= a.admittime
    AND c.charttime < a.admittime + INTERVAL 24 HOUR
  GROUP BY a.subject_id, a.hadm_id, p.gender,
           (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year))
)

SELECT
  STDDEV_SAMP(first_rr) AS sd_first_resp_rate,
  COUNT(*) AS n_admissions_used
FROM first_rr_per_admission
WHERE gender = 'F'
  AND age_at_adm BETWEEN 73 AND 83
  AND first_rr IS NOT NULL;