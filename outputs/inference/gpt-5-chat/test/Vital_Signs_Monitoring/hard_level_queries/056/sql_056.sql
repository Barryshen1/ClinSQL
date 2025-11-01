WITH hemorrhagic_stroke_patients AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime, icu.los,
         pat.gender, pat.anchor_age, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON icu.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND LOWER(dd.long_title) LIKE '%hemorrhage%'
    AND LOWER(dd.long_title) LIKE '%intracran%'
),
vitals_itemids AS (
  SELECT 
    MAX(IF(LOWER(label) LIKE '%temperature%', itemid, NULL)) AS temp_itemid,
    MAX(IF(LOWER(label) LIKE '%spo2%', itemid, NULL)) AS spo2_itemid,
    MAX(IF(LOWER(label) LIKE '%respiratory rate%', itemid, NULL)) AS rr_itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(linksto) = 'chartevents'
),
vitals AS (
  SELECT ce.stay_id,
         DATETIME_TRUNC(DATETIME(ce.charttime), HOUR) AS hour_bin,
         MAX(CASE WHEN ce.itemid = vi.temp_itemid AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever,
         MAX(CASE WHEN ce.itemid = vi.spo2_itemid AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS hypoxemia,
         MAX(CASE WHEN ce.itemid = vi.rr_itemid AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  CROSS JOIN vitals_itemids vi
  JOIN hemorrhagic_stroke_patients hsp
    ON ce.stay_id = hsp.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= hsp.intime 
    AND ce.charttime < DATETIME_ADD(hsp.intime, INTERVAL 48 HOUR)
    AND ce.itemid IN (vi.temp_itemid, vi.spo2_itemid, vi.rr_itemid)
  GROUP BY ce.stay_id, hour_bin
),
instability_per_stay AS (
  SELECT stay_id,
         SUM(fever) AS fever_hours,
         SUM(hypoxemia) AS hypoxemia_hours,
         SUM(tachypnea) AS tachypnea_hours,
         SUM(CASE WHEN fever=1 OR hypoxemia=1 OR tachypnea=1 THEN 1 ELSE 0 END) AS total_instability_hours
  FROM vitals
  GROUP BY stay_id
),
threshold AS (
  SELECT PERCENTILE_CONT(total_instability_hours, 0.9) OVER() AS p90
  FROM instability_per_stay
  LIMIT 1
),
top_decile AS (
  SELECT ips.*, hsp.los, hsp.hospital_expire_flag
  FROM instability_per_stay ips
  JOIN hemorrhagic_stroke_patients hsp
    ON ips.stay_id = hsp.stay_id
  CROSS JOIN threshold t
  WHERE ips.total_instability_hours >= t.p90
)
SELECT 
  COUNT(*) AS n_top_decile,
  AVG(los) AS mean_icu_los,
  100.0 * SUM(CASE WHEN hospital_expire_flag=1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_percent,
  AVG(fever_hours) AS mean_fever_hours,
  AVG(hypoxemia_hours) AS mean_hypoxemia_hours,
  AVG(tachypnea_hours) AS mean_tachypnea_hours
FROM top_decile;