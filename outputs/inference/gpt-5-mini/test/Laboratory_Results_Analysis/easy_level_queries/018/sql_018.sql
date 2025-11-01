WITH abg_ph_candidates AS (
  -- Candidate arterial pH measurements from ICU chartevents based on d_items labels
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS ph,
    LOWER(d.label) AS item_label
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON ce.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%ph%'
    AND (
      LOWER(d.label) LIKE '%arterial%'
      OR LOWER(d.label) LIKE '%abg%'
      OR LOWER(d.label) LIKE '%blood gas%'
    )
    AND ce.valuenum IS NOT NULL
    -- restrict to a plausible pH range to reduce clear data-entry errors
    AND ce.valuenum BETWEEN 6.0 AND 8.0
),

abg_within_admit_hour AS (
  -- Join to icustays and keep only measurements within the first hour after ICU intime
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    a.charttime,
    a.ph
  FROM abg_ph_candidates a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id
    AND a.hadm_id = i.hadm_id
    AND a.stay_id = i.stay_id
  WHERE a.charttime >= i.intime
    AND a.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 1 HOUR)
),

first_abg_per_stay AS (
  -- For each ICU stay, pick the earliest ABG pH within the admission hour
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    ph
  FROM (
    SELECT
      aw.subject_id,
      aw.hadm_id,
      aw.stay_id,
      aw.ph,
      ROW_NUMBER() OVER (PARTITION BY aw.stay_id ORDER BY aw.charttime ASC) AS rn
    FROM abg_within_admit_hour aw
  )
  WHERE rn = 1
)

-- Final: restrict to female patients and compute median pH across stays
SELECT
  approx_quantiles(f.ph, 100)[OFFSET(50)] AS median_abg_ph_on_icu_admit,
  COUNT(*) AS n_icustays_with_abg_on_admit
FROM first_abg_per_stay f
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON f.subject_id = p.subject_id
WHERE p.gender = 'F' OR LOWER(p.gender) = 'female';