WITH first_icu AS (
  SELECT s_all.*
  FROM (
    SELECT
      s.*,
      ROW_NUMBER() OVER (PARTITION BY s.subject_id ORDER BY s.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON s.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 76 AND 86
  ) s_all
  WHERE rn = 1
),

antiplatelet_rx AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'ASPIRIN|ACETYLSALICYLIC') THEN 'aspirin'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'CLOPIDOGREL|PLAVIX') THEN 'clopidogrel'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'TICAGRELOR|BRILINTA') THEN 'ticagrelor'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'PRASUGREL|EFFIENT') THEN 'prasugrel'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'TICLOPIDINE') THEN 'ticlopidine'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(drug, '')), r'DIPYRIDAMOLE') THEN 'dipyridamole'
      ELSE NULL
    END AS ap_agent
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

overlap_rx AS (
  -- prescriptions for antiplatelet agents that overlap the first ICU stay
  SELECT f.subject_id,
         f.hadm_id,
         f.stay_id,
         f.intime,
         f.outtime,
         f.los,
         ar.ap_agent,
         ar.starttime,
         ar.stoptime
  FROM first_icu f
  JOIN antiplatelet_rx ar
    ON f.subject_id = ar.subject_id
   AND f.hadm_id = ar.hadm_id
   AND ar.ap_agent IS NOT NULL
   -- overlap condition: prescription period intersects ICU period
   AND ar.starttime <= f.outtime
   AND COALESCE(ar.stoptime, ar.starttime) >= f.intime
)

SELECT
  AVG(los) AS avg_icu_los_days,
  COUNT(*) AS n_first_icustays_with_dapt
FROM (
  -- require at least two distinct antiplatelet agents overlapping the first ICU stay
  SELECT subject_id, stay_id, los, COUNT(DISTINCT ap_agent) AS n_agents
  FROM overlap_rx
  GROUP BY subject_id, stay_id, los
  HAVING n_agents >= 2
);