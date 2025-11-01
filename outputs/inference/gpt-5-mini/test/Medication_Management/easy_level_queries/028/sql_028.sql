WITH antiplatelet_presc AS (
  -- Antiplatelet prescriptions for female patients aged 44-54, joined to admission to get adm window
  SELECT
    pr.subject_id,
    pr.hadm_id,
    LOWER(COALESCE(pr.drug, '')) AS drug,
    pr.starttime,
    pr.stoptime,
    ad.admittime,
    ad.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pr.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 44 AND 54
    AND (
      LOWER(pr.drug) LIKE '%aspirin%' OR
      LOWER(pr.drug) LIKE '%clopidogrel%' OR
      LOWER(pr.drug) LIKE '%prasugrel%' OR
      LOWER(pr.drug) LIKE '%ticagrelor%' OR
      LOWER(pr.drug) LIKE '%ticlopidine%' OR
      LOWER(pr.drug) LIKE '%dipyridamole%' OR
      LOWER(pr.drug) LIKE '%cilostazol%'
    )
),
dapt_admissions AS (
  -- Identify admissions with at least two different antiplatelet agents overlapping in time (DAPT)
  SELECT DISTINCT a1.subject_id, a1.hadm_id
  FROM antiplatelet_presc a1
  JOIN antiplatelet_presc a2
    ON a1.subject_id = a2.subject_id
   AND a1.hadm_id = a2.hadm_id
   AND a1.drug != a2.drug
  WHERE
    -- Overlap test using admission-capped intervals; handle NULL stoptime by using dischtime
    COALESCE(a1.starttime, a1.admittime) <= COALESCE(a2.stoptime, a2.dischtime)
    AND COALESCE(a1.stoptime, a1.dischtime) >= COALESCE(a2.starttime, a2.admittime)
    -- Ensure positive overlap duration
    AND TIMESTAMP_DIFF(
          LEAST(COALESCE(a1.stoptime, a1.dischtime), COALESCE(a2.stoptime, a2.dischtime)),
          GREATEST(COALESCE(a1.starttime, a1.admittime), COALESCE(a2.starttime, a2.admittime)),
          SECOND
        ) > 0
),
dapt_presc_durations AS (
  -- For prescriptions within DAPT admissions, compute per-prescription duration (days),
  -- capping to the admission window
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.drug,
    -- cap prescription interval to [admittime, dischtime]
    TIMESTAMP_DIFF(
      LEAST(COALESCE(ap.stoptime, ap.dischtime), ap.dischtime),
      GREATEST(ap.starttime, ap.admittime),
      DAY
    ) AS duration_days
  FROM antiplatelet_presc ap
  JOIN dapt_admissions d
    USING(subject_id, hadm_id)
  WHERE ap.starttime IS NOT NULL
)
SELECT
  -- Sample standard deviation of per-prescription durations (in days)
  STDDEV_SAMP(duration_days) AS sd_duration_days,
  COUNT(*) AS prescriptions_count
FROM dapt_presc_durations
WHERE duration_days > 0;