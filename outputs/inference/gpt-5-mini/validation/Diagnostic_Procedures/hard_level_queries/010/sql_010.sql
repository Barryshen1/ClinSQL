WITH eligible_stays AS (
  -- ICU stays for male patients age 40-50 with admission info and a hemorrhagic-stroke flag (heuristic)
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = icu.hadm_id
        AND (
          LOWER(dd.long_title) LIKE '%hemorrhag%' OR
          LOWER(dd.long_title) LIKE '%haemorrh%' OR
          LOWER(dd.long_title) LIKE '%subarachnoid%' OR
          LOWER(dd.long_title) LIKE '%intracerebral%' OR
          LOWER(dd.long_title) LIKE '%intracranial%'
        )
    ) THEN 1 ELSE 0 END AS hemorrhagic_stroke
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

procs_per_stay AS (
  -- For each eligible ICU stay, count procedures_icd rows within 72 hours of ICU intime
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.anchor_age,
    s.gender,
    s.hospital_expire_flag,
    s.hemorrhagic_stroke,
    COUNT(pr.icd_code) AS num_procs
  FROM eligible_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.subject_id = s.subject_id
   AND pr.hadm_id = s.hadm_id
   AND pr.chartdate IS NOT NULL
   -- include procedures with chartdate on dates between intime and intime+72h (chartdate is DATE)
   AND pr.chartdate BETWEEN DATE(s.intime) AND DATE(TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR))
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id, s.intime, s.outtime, s.los,
    s.anchor_age, s.gender, s.hospital_expire_flag, s.hemorrhagic_stroke
),

group_p90 AS (
  -- Compute 90th percentile of procedure counts for each group (hemorrhagic vs other)
  SELECT
    hemorrhagic_stroke,
    APPROX_QUANTILES(num_procs, 100)[OFFSET(90)] AS p90,
    COUNT(*) AS n_stays
  FROM procs_per_stay
  GROUP BY hemorrhagic_stroke
)

-- Final: for each group, report the 90th percentile and metrics among stays at/above that percentile
SELECT
  g.hemorrhagic_stroke,
  g.p90 AS procedures_p90,
  g.n_stays AS total_stays_in_group,
  -- define top-decile as num_procs >= ceil(p90)
  SUM(CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) THEN 1 ELSE 0 END) AS n_top_decile_stays,
  -- mean ICU LOS among top-decile stays
  SAFE_DIVIDE(
    SUM(CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) THEN p.los ELSE 0 END),
    NULLIF(SUM(CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) THEN 1 ELSE 0 END), 0)
  ) AS mean_icu_los_top_decile,
  -- median ICU LOS among top-decile stays (approximate)
  APPROX_QUANTILES(
    CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) THEN p.los ELSE NULL END,
    2
  )[OFFSET(1)] AS median_icu_los_top_decile,
  -- in-hospital mortality rate among top-decile stays
  SAFE_DIVIDE(
    SUM(CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) AND p.hospital_expire_flag = 1 THEN 1 ELSE 0 END),
    NULLIF(SUM(CASE WHEN p.num_procs >= CAST(CEIL(g.p90) AS INT64) THEN 1 ELSE 0 END), 0)
  ) AS inhospital_mortality_rate_top_decile
FROM group_p90 g
LEFT JOIN procs_per_stay p
  ON p.hemorrhagic_stroke = g.hemorrhagic_stroke
GROUP BY g.hemorrhagic_stroke, g.p90, g.n_stays
ORDER BY g.hemorrhagic_stroke DESC;