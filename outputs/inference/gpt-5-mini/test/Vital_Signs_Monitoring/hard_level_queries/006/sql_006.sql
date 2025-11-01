WITH ugib_admissions AS (
  -- Admissions with a diagnosis whose long_title mentions both 'gastrointestinal' and 'hemorrhag'
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%gastrointestinal%'
    AND LOWER(dd.long_title) LIKE '%hemorrhag%'
),

cohort_stays AS (
  -- ICU stays for male patients age 60-70 in UGIB admissions
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR) AS end48,
    ic.outtime,
    ic.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ic.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND ic.hadm_id IN (SELECT hadm_id FROM ugib_admissions)
),

vital_rows AS (
  -- Pull HR, MAP, RR measurements in the first 48 hours for the cohort
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    ce.charttime,
    di.label AS item_label,
    ce.valuenum,
    CASE WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr%' THEN ce.valuenum END AS hr_val,
    CASE WHEN LOWER(di.label) LIKE '%mean arterial%' OR LOWER(di.label) LIKE '%map%' THEN ce.valuenum END AS map_val,
    CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%respirations%' OR LOWER(di.label) LIKE '%rr%' THEN ce.valuenum END AS rr_val
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cs.subject_id = ce.subject_id
   AND cs.hadm_id = ce.hadm_id
   AND cs.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN cs.intime AND cs.end48
    AND ce.valuenum IS NOT NULL
    -- keep rows that appear to be one of the vitals of interest
    AND (
      LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%mean arterial%'
      OR LOWER(di.label) LIKE '%map%'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%resp rate%'
      OR LOWER(di.label) LIKE '%respirations%'
      OR LOWER(di.label) LIKE '%hr%'
      OR LOWER(di.label) LIKE '%rr%'
    )
),

per_stay_aggregates AS (
  -- Aggregate per ICU stay: counts, binary flags, and instability index
  SELECT
    cs.stay_id,
    cs.subject_id,
    cs.hadm_id,
    cs.los,
    cs.hospital_expire_flag,
    COUNT(*) AS total_vital_rows,
    SUM(CASE WHEN vr.hr_val IS NOT NULL THEN 1 ELSE 0 END) AS hr_rows,
    SUM(CASE WHEN vr.map_val IS NOT NULL THEN 1 ELSE 0 END) AS map_rows,
    SUM(CASE WHEN vr.rr_val IS NOT NULL THEN 1 ELSE 0 END) AS rr_rows,
    SUM(CASE WHEN vr.hr_val IS NOT NULL AND vr.hr_val > 100 THEN 1 ELSE 0 END) AS hr_pos_count,
    SUM(CASE WHEN vr.map_val IS NOT NULL AND vr.map_val < 65 THEN 1 ELSE 0 END) AS map_pos_count,
    SUM(CASE WHEN vr.rr_val IS NOT NULL AND vr.rr_val > 20 THEN 1 ELSE 0 END) AS rr_pos_count,
    SUM(CASE
          WHEN ( (vr.hr_val IS NOT NULL AND vr.hr_val > 100)
               OR (vr.map_val IS NOT NULL AND vr.map_val < 65)
               OR (vr.rr_val IS NOT NULL AND vr.rr_val > 20)
              )
         THEN 1 ELSE 0 END) AS instability_count
  FROM cohort_stays cs
  LEFT JOIN vital_rows vr
    ON cs.stay_id = vr.stay_id
  GROUP BY cs.stay_id, cs.subject_id, cs.hadm_id, cs.los, cs.hospital_expire_flag
),

per_stay_index AS (
  -- compute index and binary flags; exclude stays with zero vital rows when calculating index later
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    los,
    hospital_expire_flag,
    total_vital_rows,
    hr_rows,
    map_rows,
    rr_rows,
    hr_pos_count,
    map_pos_count,
    rr_pos_count,
    instability_count,
    SAFE_DIVIDE(instability_count, NULLIF(total_vital_rows,0)) AS instability_index,
    CASE WHEN hr_pos_count > 0 THEN 1 ELSE 0 END AS had_tachycardia,
    CASE WHEN map_pos_count > 0 THEN 1 ELSE 0 END AS had_map_low,
    CASE WHEN rr_pos_count > 0 THEN 1 ELSE 0 END AS had_tachypnea
  FROM per_stay_aggregates
),

pcts AS (
  SELECT
    (SELECT APPROX_QUANTILES(instability_index, 100)[OFFSET(90)]
     FROM per_stay_index
     WHERE instability_index IS NOT NULL) AS p90,
    (SELECT APPROX_QUANTILES(instability_index, 100)[OFFSET(95)]
     FROM per_stay_index
     WHERE instability_index IS NOT NULL) AS p95
)

-- Final outputs: include the 95th percentile and compare top decile vs others
SELECT
  CASE WHEN psi.instability_index >= p.p90 THEN 'top_decile' ELSE 'other' END AS group_label,
  COUNT(1) AS n_stays,
  ROUND(100.0 * AVG(psi.had_tachycardia),2) AS pct_had_tachycardia,
  ROUND(100.0 * AVG(psi.had_map_low),2) AS pct_had_MAP_lt_65,
  ROUND(100.0 * AVG(psi.had_tachypnea),2) AS pct_had_tachypnea,
  ROUND(AVG(psi.los),2) AS mean_ICU_LOS_days,
  ROUND(100.0 * AVG(psi.hospital_expire_flag),2) AS pct_hospital_mortality,
  p.p90 AS instability_index_p90,
  p.p95 AS instability_index_p95
FROM per_stay_index psi
CROSS JOIN pcts p
WHERE psi.instability_index IS NOT NULL
GROUP BY group_label, p.p90, p.p95
ORDER BY group_label;