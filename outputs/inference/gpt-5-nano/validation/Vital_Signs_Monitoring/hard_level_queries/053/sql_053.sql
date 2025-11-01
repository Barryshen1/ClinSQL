WITH shock_adms AS (
  -- Mark admissions with a shock diagnosis
  SELECT DISTINCT di.hadm_id, 1 AS shock_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%shock%'
),

base_stays AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    IFNULL(sa.shock_flag, 0) AS shock_flag,
    CASE
      WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  LEFT JOIN shock_adms sa
    ON i.hadm_id = sa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 59 AND 69
),

map_reads AS (
  SELECT
    bs.stay_id,
    COUNT(*) AS total_map,
    SUM(CASE WHEN c.valuenum < 65 THEN 1 ELSE 0 END) AS hypot_count
  FROM base_stays bs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON bs.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    AND c.charttime >= bs.intime
    AND c.charttime < TIMESTAMP_ADD(bs.intime, INTERVAL 24 HOUR)
  GROUP BY bs.stay_id
),

tach_reads AS (
  SELECT
    bs.stay_id,
    COUNT(*) AS total_hr,
    SUM(CASE WHEN c.valuenum > 100 THEN 1 ELSE 0 END) AS tach_count
  FROM base_stays bs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS c
    ON bs.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON c.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%heart rate%'
    AND c.charttime >= bs.intime
    AND c.charttime < TIMESTAMP_ADD(bs.intime, INTERVAL 24 HOUR)
  GROUP BY bs.stay_id
),

per_stay AS (
  SELECT
    bs.stay_id,
    bs.hadm_id,
    bs.intime,
    bs.los,
    bs.mortality,
    bs.shock_flag,
    COALESCE(mr.total_map, 0) AS total_map,
    COALESCE(mr.hypot_count, 0) AS hypot_count,
    COALESCE(tr.total_hr, 0) AS total_hr,
    COALESCE(tr.tach_count, 0) AS tach_count
  FROM base_stays bs
  LEFT JOIN map_reads mr ON bs.stay_id = mr.stay_id
  LEFT JOIN tach_reads tr ON bs.stay_id = tr.stay_id
),

burden_vals AS (
  SELECT
    CASE WHEN s.shock_flag = 1 THEN 'Shock' ELSE 'No_Shock' END AS shock_group,
    IF(s.total_map > 0, s.hypot_count * 1.0 / s.total_map, 0) +
      IF(s.total_hr > 0, s.tach_count * 1.0 / s.total_hr, 0) AS comp_instab,
    IF(s.total_map > 0, s.hypot_count * 1.0 / s.total_map, 0) AS hypot_burden,
    IF(s.total_hr > 0, s.tach_count * 1.0 / s.total_hr, 0) AS tach_burden,
    s.los AS los,
    s.mortality AS mortality
  FROM per_stay s
)

SELECT
  shock_group,
  (APPROX_QUANTILES(comp_instab, 4))[OFFSET(1)] AS comp_instab_p25,
  (APPROX_QUANTILES(comp_instab, 4))[OFFSET(2)] AS comp_instab_p50,
  (APPROX_QUANTILES(comp_instab, 4))[OFFSET(3)] AS comp_instab_p75,
  AVG(comp_instab) AS mean_composite_instability,
  (APPROX_QUANTILES(hypot_burden, 4))[OFFSET(1)] AS hypot_p25,
  (APPROX_QUANTILES(hypot_burden, 4))[OFFSET(2)] AS hypot_median,
  (APPROX_QUANTILES(hypot_burden, 4))[OFFSET(3)] AS hypot_p75,
  AVG(hypot_burden) AS mean_hypot_burden,
  (APPROX_QUANTILES(tach_burden, 4))[OFFSET(1)] AS tach_p25,
  (APPROX_QUANTILES(tach_burden, 4))[OFFSET(2)] AS tach_median,
  (APPROX_QUANTILES(tach_burden, 4))[OFFSET(3)] AS tach_p75,
  AVG(tach_burden) AS mean_tach_burden,
  (APPROX_QUANTILES(los, 4))[OFFSET(1)] AS los_p25,
  (APPROX_QUANTILES(los, 4))[OFFSET(2)] AS los_median,
  (APPROX_QUANTILES(los, 4))[OFFSET(3)] AS los_p75,
  AVG(los) AS mean_los,
  AVG(mortality) AS mortality_rate
FROM burden_vals
GROUP BY shock_group
ORDER BY shock_group;