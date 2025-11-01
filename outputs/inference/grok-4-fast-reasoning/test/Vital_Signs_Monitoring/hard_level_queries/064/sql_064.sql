WITH arf_diagnoses AS (
  -- Identify admissions with ARF (Acute Renal Failure) diagnosis
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '584.%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
),
eligible_stays AS (
  -- Male ICU stays for ages 45-55 with ARF
  SELECT p.subject_id, i.stay_id, i.hadm_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  JOIN arf_diagnoses ad ON i.subject_id = ad.subject_id AND i.hadm_id = ad.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 45 AND 55
),
hr_map_itemids AS (
  -- Item IDs for HR and MAP from d_items (Vital Signs category)
  SELECT itemid,
    CASE 
      WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%pulse%' THEN 'HR'
      WHEN (LOWER(label) LIKE '%mean%' AND (LOWER(label) LIKE '%arterial%' OR LOWER(label) LIKE '%map%')) THEN 'MAP'
    END AS vtype
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Vital Signs'
    AND (
      LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%pulse%' 
      OR 
      (LOWER(label) LIKE '%mean%' AND (LOWER(label) LIKE '%arterial%' OR LOWER(label) LIKE '%map%'))
    )
),
first48_vitals AS (
  -- Vital signs in first 48 hours for score calculation
  SELECT 
    es.stay_id, h.vtype, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN eligible_stays es ON ce.stay_id = es.stay_id
  JOIN hr_map_itemids h ON ce.itemid = h.itemid
  WHERE ce.charttime >= es.intime
    AND ce.charttime < TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
instability_scores AS (
  -- Composite score: count of abnormal readings (HR >100 or MAP <65)
  SELECT 
    stay_id,
    COUNTIF((vtype = 'HR' AND valuenum > 100) OR (vtype = 'MAP' AND valuenum < 65)) AS score
  FROM first48_vitals
  GROUP BY stay_id
),
whole_stay_vitals AS (
  -- Vital signs over entire stay for outcome incidence
  SELECT 
    es.stay_id, h.vtype, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN eligible_stays es ON ce.stay_id = es.stay_id
  JOIN hr_map_itemids h ON ce.itemid = h.itemid
  WHERE ce.charttime >= es.intime
    AND ce.charttime < es.outtime
    AND ce.valuenum IS NOT NULL
),
has_hypotension AS (
  SELECT 
    stay_id,
    MAX(CASE WHEN vtype = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS has_hypo
  FROM whole_stay_vitals
  GROUP BY stay_id
),
has_tachycardia AS (
  SELECT 
    stay_id,
    MAX(CASE WHEN vtype = 'HR' AND valuenum > 100 THEN 1 ELSE 0 END) AS has_tachy
  FROM whole_stay_vitals
  GROUP BY stay_id
),
admissions_mort AS (
  -- Mortality from admissions
  SELECT 
    a.hadm_id, 
    CAST(a.hospital_expire_flag AS INT64) AS hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_stays es ON a.hadm_id = es.hadm_id
),
all_eligible_with_flags AS (
  -- Combine all data per stay
  SELECT 
    es.stay_id, es.hadm_id, es.los,
    COALESCE(iscore.score, 0) AS score,
    COALESCE(hh.has_hypo, 0) AS has_hypo,
    COALESCE(ht.has_tachy, 0) AS has_tachy,
    COALESCE(am.hospital_expire_flag, 0) AS mortality
  FROM eligible_stays es
  LEFT JOIN instability_scores iscore ON es.stay_id = iscore.stay_id
  LEFT JOIN has_hypotension hh ON es.stay_id = hh.stay_id
  LEFT JOIN has_tachycardia ht ON es.stay_id = ht.stay_id
  LEFT JOIN admissions_mort am ON es.hadm_id = am.hadm_id
),
q75 AS (
  -- 75th percentile threshold for top quartile
  SELECT PERCENTILE_CONT(score, 0.75) AS threshold
  FROM all_eligible_with_flags
),
top_stays AS (
  SELECT aewf.*
  FROM all_eligible_with_flags aewf
  CROSS JOIN q75
  WHERE aewf.score > q75.threshold
),
lower_stays AS (
  SELECT aewf.*
  FROM all_eligible_with_flags aewf
  CROSS JOIN q75
  WHERE aewf.score <= q75.threshold
),
p95 AS (
  -- 95th percentile instability score
  SELECT ROUND(PERCENTILE_CONT(score, 0.95), 2) AS p95_instability_score
  FROM all_eligible_with_flags
),
top_hypo AS (SELECT ROUND(AVG(has_hypo) * 100, 2) AS top_hypo_pct FROM top_stays),
top_tachy AS (SELECT ROUND(AVG(has_tachy) * 100, 2) AS top_tachy_pct FROM top_stays),
top_los AS (SELECT ROUND(AVG(los), 2) AS top_avg_los FROM top_stays),
top_mort AS (SELECT ROUND(AVG(mortality) * 100, 2) AS top_mort_pct FROM top_stays),
lower_hypo AS (SELECT ROUND(AVG(has_hypo) * 100, 2) AS lower_hypo_pct FROM lower_stays),
lower_tachy AS (SELECT ROUND(AVG(has_tachy) * 100, 2) AS lower_tachy_pct FROM lower_stays),
lower_los AS (SELECT ROUND(AVG(los), 2) AS lower_avg_los FROM lower_stays),
lower_mort AS (SELECT ROUND(AVG(mortality) * 100, 2) AS lower_mort_pct FROM lower_stays)
-- Final output: one row with 95th percentile and comparisons (top vs. lower cohort)
SELECT 
  p95.p95_instability_score,
  th.top_hypo_pct,
  tt.top_tachy_pct,
  tl.top_avg_los,
  tm.top_mort_pct,
  lh.lower_hypo_pct,
  lt.lower_tachy_pct,
  ll.lower_avg_los,
  lm.lower_mort_pct
FROM p95
CROSS JOIN top_hypo th
CROSS JOIN top_tachy tt
CROSS JOIN top_los tl
CROSS JOIN top_mort tm
CROSS JOIN lower_hypo lh
CROSS JOIN lower_tachy lt
CROSS JOIN lower_los ll
CROSS JOIN lower_mort lm;