with ca_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE (p.gender = 'M' OR p.gender = 'Male')
    AND p.anchor_age BETWEEN 55 AND 65
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = i.subject_id
        AND di.hadm_id = i.hadm_id
        AND LOWER(dd.long_title) LIKE '%cardiac arrest%'
    )
),

-- Pull vitals within first 24h of ICU stay, mapped to vital groups
vitals_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' THEN 'HR'
      WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN 'RR'
      WHEN LOWER(di.label) LIKE '%systolic blood pressure%' THEN 'SBP'
      WHEN LOWER(di.label) LIKE '%diastolic blood pressure%' THEN 'DBP'
      WHEN LOWER(di.label) LIKE '%mean arterial pressure%' THEN 'MAP'
      WHEN LOWER(di.label) LIKE '%temperature%' THEN 'Temp'
      WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' THEN 'SpO2'
      ELSE NULL
    END AS vitals_group,
    ce.valuenum
  FROM ca_cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = c.subject_id
   AND ce.hadm_id = c.hadm_id
   AND ce.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
),

-- Compute per-stay per-vital-range
vital_ranges AS (
  SELECT
    stay_id,
    vitals_group,
    MAX(valuenum) - MIN(valuenum) AS grp_range
  FROM vitals_24h
  WHERE vitals_group IS NOT NULL
  GROUP BY stay_id, vitals_group
),

-- Total instability for each stay (sum of ranges across vitals)
instability_raw AS (
  SELECT
    stay_id,
    SUM(IFNULL(grp_range, 0)) AS instability_raw
  FROM vital_ranges
  GROUP BY stay_id
),

-- Normalize to 0-100 scale
instability_norm AS (
  SELECT
    ir.stay_id,
    ir.instability_raw,
    MIN(ir.instability_raw) OVER () AS min_ir,
    MAX(ir.instability_raw) OVER () AS max_ir
  FROM instability_raw ir
),

instability_score AS (
  SELECT
    inr.stay_id,
    CASE
      WHEN max_ir > min_ir THEN 100.0 * (inr.instability_raw - min_ir) / (max_ir - min_ir)
      ELSE 0.0
    END AS instability_score
  FROM instability_norm inr
),

-- Join back to ICU stays and admissions to get LOS and death flag
final_stays AS (
  SELECT
    iscore.stay_id,
    iscore.instability_score,
    icu.los AS icu_los,
    a.hospital_expire_flag AS death_flag
  FROM instability_score AS iscore
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON iscore.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON icu.hadm_id = a.hadm_id
),

-- Decile assignment to identify the most unstable decile (top 10%)
deciled AS (
  SELECT
    stay_id,
    instability_score,
    icu_los,
    death_flag,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM final_stays
)

-- Final outputs:
-- 1) percentile of a score of 70
-- 2) mean ICU LOS and mortality for the most unstable decile (decile = 1)
SELECT
  -- Percentile (proportion of stays with instability_score <= 70)
  100.0 * SUM(CASE WHEN instability_score <= 70.0 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_of_70,
  -- Mean ICU LOS for the most unstable decile (top 10%)
  AVG(CASE WHEN decile = 1 THEN icu_los END) AS mean_icu_los_top_decile,
  -- Mortality (in-hospital) for the most unstable decile
  SUM(CASE WHEN decile = 1 AND death_flag = 1 THEN 1 ELSE 0 END) /
  NULLIF(SUM(CASE WHEN decile = 1 THEN 1 ELSE 0 END), 0) AS mortality_top_decile
FROM deciled;