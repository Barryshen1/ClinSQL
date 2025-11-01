WITH ARF AS (
  -- Select male patients aged 45-55 with ARF in the ICU
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = icu.subject_id AND di.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
    ON dic.icd_code = di.icd_code AND dic.icd_version = di.icd_version
  WHERE
    UPPER(p.gender) = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dic.long_title) LIKE '%acute respiratory failure%'
),
VITALS AS (
  -- Compute map_low, hr_tachy, rr_tachy over the first 48 hours
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    MAX(CASE
          WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%'
               THEN CASE WHEN ce.valuenum IS NOT NULL AND ce.valuenum < 65 THEN 1 ELSE 0 END
          ELSE 0
        END) AS map_low,
    MAX(CASE
          WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%'
               THEN CASE WHEN ce.valuenum IS NOT NULL AND ce.valuenum > 100 THEN 1 ELSE 0 END
          ELSE 0
        END) AS hr_tachy,
    MAX(CASE
          WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%'
               THEN CASE WHEN ce.valuenum IS NOT NULL AND ce.valuenum > 28 THEN 1 ELSE 0 END
          ELSE 0
        END) AS rr_tachy
  FROM ARF AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = a.subject_id
   AND ce.hadm_id = a.hadm_id
   AND ce.stay_id = a.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE ce.charttime BETWEEN a.intime AND TIMESTAMP_ADD(a.intime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.stay_id
),
ARF_LOS_DEATH AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    icu.los AS icu_los,
    IF(adm.deathtime IS NOT NULL, 1, 0) AS death_flag,
    COALESCE(v.map_low, 0) AS map_low,
    COALESCE(v.hr_tachy, 0) AS hr_tachy,
    COALESCE(v.rr_tachy, 0) AS rr_tachy,
    (COALESCE(v.map_low,0) + COALESCE(v.hr_tachy,0) + COALESCE(v.rr_tachy,0)) AS instability_score
  FROM ARF a
  LEFT JOIN VITALS v
    ON v.subject_id = a.subject_id
   AND v.hadm_id = a.hadm_id
   AND v.stay_id = a.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id AND icu.stay_id = a.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.hadm_id = a.hadm_id
),
P95 AS (
  -- 95th percentile of the instability score
  SELECT CAST(APPROX_QUANTILES(instability_score, 100)[OFFSET(94)] AS FLOAT64) AS instability_p95
  FROM ARF_LOS_DEATH
)
SELECT
  'instability_p95' AS metric,
  instability_p95 AS value,
  NULL AS pct_map_low,
  NULL AS pct_hr_tachy,
  NULL AS mean_icu_los,
  NULL AS mortality_rate,
  NULL AS group_label
FROM P95

UNION ALL

SELECT
  CASE WHEN quartile = 1 THEN 'Top quartile' ELSE 'Other quartiles' END AS metric,
  NULL AS value,
  AVG(CAST(map_low AS FLOAT64)) AS pct_map_low,
  AVG(CAST(hr_tachy AS FLOAT64)) AS pct_hr_tachy,
  AVG(icu_los) AS mean_icu_los,
  AVG(CAST(death_flag AS FLOAT64)) AS mortality_rate,
  NULL AS group_label
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    icu.los AS icu_los,
    -- ensure death_flag is numeric (1/0), not boolean
    IF(adm.deathtime IS NOT NULL, 1, 0) AS death_flag,
    COALESCE(v.map_low, 0) AS map_low,
    COALESCE(v.hr_tachy, 0) AS hr_tachy,
    COALESCE(v.rr_tachy, 0) AS rr_tachy,
    (COALESCE(v.map_low,0) + COALESCE(v.hr_tachy,0) + COALESCE(v.rr_tachy,0)) AS instability_score,
    NTILE(4) OVER (ORDER BY (COALESCE(v.map_low,0) + COALESCE(v.hr_tachy,0) + COALESCE(v.rr_tachy,0)) DESC) AS quartile
  FROM ARF a
  LEFT JOIN VITALS v
    ON v.subject_id = a.subject_id AND v.hadm_id = a.hadm_id AND v.stay_id = a.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.subject_id = a.subject_id AND icu.hadm_id = a.hadm_id AND icu.stay_id = a.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON adm.hadm_id = a.hadm_id
) AS sub
GROUP BY
  CASE WHEN quartile = 1 THEN 'Top quartile' ELSE 'Other quartiles' END
ORDER BY metric;