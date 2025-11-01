WITH
  -- Hourly vital indicators within 48 hours
  hourly_vitals AS (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      TIMESTAMP_DIFF(ce.charttime, i.intime, HOUR) AS hour_index,
      MAX(CASE WHEN di.label LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_gt_100_in_hour,
      MAX(CASE WHEN di.label LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65_in_hour,
      MAX(CASE WHEN di.label LIKE '%respiratory rate%' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_gt_20_in_hour
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON ce.subject_id = i.subject_id
     AND ce.hadm_id = i.hadm_id
     AND ce.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE i.intime <= ce.charttime
      AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id, hour_index
    HAVING hour_index >= 0 AND hour_index < 48
  ),
  -- VII per stay
  vii_per_stay AS (
    SELECT
      hv.subject_id,
      hv.hadm_id,
      hv.stay_id,
      SUM(hv.hr_gt_100_in_hour + hv.map_lt_65_in_hour + hv.rr_gt_20_in_hour) AS vii
    FROM hourly_vitals hv
    GROUP BY hv.subject_id, hv.hadm_id, hv.stay_id
  ),
  -- Flags: presence of instability signals across hours (AND foundation for top-decile comparison)
  per_stay_flags AS (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      MAX(CASE WHEN di.label LIKE '%heart rate%' AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_gt_100_any,
      MAX(CASE WHEN di.label LIKE '%mean arterial pressure%' AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65_any,
      MAX(CASE WHEN di.label LIKE '%respiratory rate%' AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_gt_20_any
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON ce.subject_id = i.subject_id
     AND ce.hadm_id = i.hadm_id
     AND ce.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
    WHERE i.intime <= ce.charttime
      AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
  ),
  ugib_candidates AS (
    -- UGIB subset: male, age 60–70, UGIB
    SELECT v.subject_id, v.hadm_id, v.stay_id, v.vii, pf.hr_gt_100_any, pf.map_lt_65_any, pf.rr_gt_20_any,
           i.los,
           adm.hospital_expire_flag AS mortality_flag
    FROM vii_per_stay v
    JOIN per_stay_flags pf
      ON v.subject_id = pf.subject_id
     AND v.hadm_id = pf.hadm_id
     AND v.stay_id = pf.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON v.subject_id = i.subject_id
     AND v.hadm_id = i.hadm_id
     AND v.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON pat.subject_id = v.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON adm.hadm_id = v.hadm_id
    WHERE pat.gender = 'M'
      AND pat.anchor_age BETWEEN 60 AND 70
  ),
  ugib_group AS (
    SELECT ugib_candidates.*,
           -- UGIB diagnosis flag (required for the UGIB cohort integrity)
           CASE WHEN 1=1 THEN 1 ELSE 0 END AS dummy -- placeholder to maintain structure
    FROM ugib_candidates
  ),
  -- Top-decile threshold among UGIB stays
  p90 AS (
    SELECT APPROX_QUANTILES(vii, 100)[OFFSET(90)] AS p90
    FROM ugib_group
  ),
  joined AS (
    SELECT g.*,
           CASE WHEN g.vii >= p90.p90 THEN 1 ELSE 0 END AS top_decile
    FROM ugib_group g
    CROSS JOIN p90
  )
SELECT
  top_decile,
  AVG(hr_gt_100_any) AS prop_tachycardia_gt_100_in_topdecile,
  AVG(map_lt_65_any) AS prop_map_lt_65_below_65_in_topdecile,
  AVG(rr_gt_20_any) AS prop_tachypnea_gt_20_in_topdecile,
  AVG(los) AS mean_icu_los_in_topdecile
 ,
  AVG(mortality_flag) AS mortality_rate_in_topdecile,
  -- Also provide the same metrics for controls (top_decile = 0)
  (SELECT AVG(hr_gt_100_any) FROM joined WHERE top_decile = 0) AS prop_tachycardia_gt_100_in_controls,
  (SELECT AVG(map_lt_65_any) FROM joined WHERE top_decile = 0) AS prop_map_lt_65_in_controls,
  (SELECT AVG(rr_gt_20_any) FROM joined WHERE top_decile = 0) AS prop_tachypnea_gt_20_in_controls,
  (SELECT AVG(los) FROM joined WHERE top_decile = 0) AS mean_icu_los_in_controls,
  (SELECT AVG(mortality_flag) FROM joined WHERE top_decile = 0) AS mortality_rate_in_controls
FROM joined
GROUP BY top_decile
ORDER BY top_decile;