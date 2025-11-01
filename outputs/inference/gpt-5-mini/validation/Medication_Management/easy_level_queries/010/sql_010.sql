WITH nitrate_rx AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime AS rx_start,
    p.stoptime AS rx_stop,
    a.admittime,
    a.dischtime,
    -- effective start: latest of prescription start (or admission if null) and admission time
    GREATEST(COALESCE(p.starttime, a.admittime), a.admittime) AS eff_start,
    -- effective end: earliest of prescription stop (or discharge if null) and discharge time
    LEAST(COALESCE(p.stoptime, a.dischtime), a.dischtime) AS eff_end
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 73 AND 83
    -- basic name-based nitrate identification (adjust as needed)
    AND (
      LOWER(p.drug) LIKE '%nitro%' 
      OR LOWER(p.drug) LIKE '%nitrate%' 
      OR LOWER(p.drug) LIKE '%isosorbide%'
    )
)

SELECT
  STDDEV_SAMP(duration_days) AS sd_duration_days,
  COUNT(*) AS n_prescriptions
FROM (
  SELECT
    *,
    -- duration in days as a float
    TIMESTAMP_DIFF(eff_end, eff_start, SECOND) / 86400.0 AS duration_days
  FROM nitrate_rx
)
WHERE eff_end > eff_start;